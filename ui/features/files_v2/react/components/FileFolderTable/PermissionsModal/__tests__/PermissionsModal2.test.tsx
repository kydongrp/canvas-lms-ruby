/*
 * Copyright (C) 2025 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import {render, screen, waitFor} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import doFetchApi from '@canvas/do-fetch-api-effect'
import {FileManagementProvider} from '../../../../contexts/FileManagementContext'
import {createMockFileManagementContext} from '../../../../__tests__/createMockContext'
import {FAKE_FILES, FAKE_FOLDERS_AND_FILES} from '../../../../../fixtures/fakeData'
import {resetAndGetFilesEnv} from '../../../../../utils/filesEnvUtils'
import {createFilesContexts} from '../../../../../fixtures/fileContexts'
import {RowsProvider} from '../../../../contexts/RowsContext'
import PermissionsModal from '../PermissionsModal'
import {
  type AvailabilityOptionId,
  DATE_RANGE_TYPE_OPTIONS,
  parseNewRows,
} from '../PermissionsModalUtils'

jest.mock('@canvas/do-fetch-api-effect')

const defaultProps = {
  open: true,
  items: FAKE_FOLDERS_AND_FILES,
  onDismiss: jest.fn(),
}

const renderComponent = (props?: any) =>
  render(
    <FileManagementProvider value={createMockFileManagementContext()}>
      <RowsProvider value={{currentRows: FAKE_FOLDERS_AND_FILES, setCurrentRows: jest.fn()}}>
        <PermissionsModal {...defaultProps} {...props} />
      </RowsProvider>
    </FileManagementProvider>,
  )

describe('PermissionsModal', () => {
  beforeEach(() => {
    // Reset the environment before each test
    const filesContexts = createFilesContexts()
    resetAndGetFilesEnv(filesContexts)
    // Set up a default mock implementation for doFetchApi to prevent unhandled rejections
    ;(doFetchApi as jest.Mock).mockResolvedValue({})
  })

  afterEach(() => {
    jest.clearAllMocks()
    jest.resetAllMocks()
    // Reset the environment after each test to ensure clean state
    const filesContexts = createFilesContexts()
    resetAndGetFilesEnv(filesContexts)
  })

  it('performs fetch request and shows alert', async () => {
    renderComponent({
      items: [Object.assign({}, FAKE_FILES[0], {usage_rights: {}})],
    })

    // PUT request response
    ;(doFetchApi as jest.Mock).mockResolvedValueOnce({})
    await userEvent.click(screen.getByTestId('permissions-save-button'))

    await waitFor(() => {
      expect(screen.getAllByText(/permissions have been successfully set./i)[0]).toBeInTheDocument()
      expect(doFetchApi).toHaveBeenCalledWith({
        body: {
          hidden: false,
          lock_at: '',
          locked: false,
          unlock_at: '',
          visibility_level: 'inherit',
        },
        method: 'PUT',
        path: '/api/v1/files/178',
      })
    })
  })

  it('fails fetch request and shows alert', async () => {
    renderComponent({
      items: [Object.assign({}, FAKE_FILES[0], {usage_rights: {}})],
    })

    // PUT request response
    ;(doFetchApi as jest.Mock).mockRejectedValue({})
    await userEvent.click(await screen.getByTestId('permissions-save-button'))

    await waitFor(() => {
      expect(
        screen.getAllByText(/an error occurred while setting permissions. please try again./i)[0],
      ).toBeInTheDocument()
      expect(doFetchApi).toHaveBeenCalledWith({
        body: {
          hidden: false,
          lock_at: '',
          locked: false,
          unlock_at: '',
          visibility_level: 'inherit',
        },
        method: 'PUT',
        path: '/api/v1/files/178',
      })
    })
  })

  it('with alert after trying to save', async () => {
    const usageFilesContexts = createFilesContexts({
      usageRightsRequired: true,
    })
    resetAndGetFilesEnv(usageFilesContexts)

    const {getByTestId} = renderComponent()

    await userEvent.click(getByTestId('permissions-save-button'))

    // Wait for any state updates and re-renders
    await waitFor(async () => {
      const alert = await screen.findByText(
        'Selected items must have usage rights assigned before they can be published.',
      )
      expect(alert).toBeInTheDocument()
    })
  })
})
