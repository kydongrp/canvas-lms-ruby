/*
 * Copyright (C) 2024 - present Instructure, Inc.
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

import {useState, useCallback} from 'react'

import doFetchApi from '@canvas/do-fetch-api-effect'
import {buildContextPath} from './buildContextPath'
import {ApiCallStatus} from './ApiCallStatus'
import type {AssignmentUsedLocation} from '@canvas/grading_scheme/gradingSchemeApiModel'

export const useGradingSchemeAssignmentUsedLocations = (): {
  getGradingSchemeAssignmentUsedLocations: (
    contextType: 'Account' | 'Course',
    contextId: string,
    gradingSchemeId: string,
    courseId: string,
    nextPagePath?: string,
  ) => Promise<{
    assignmentUsedLocations: AssignmentUsedLocation[]
    isLastPage: boolean
    nextPage: string
  }>
  gradingSchemeAssignmentUsedLocationsStatus: string
} => {
  const [
    gradingSchemeAssignmentUsedLocationsStatus,
    setGradingSchemeAssignmentUsedLocationsStatus,
  ] = useState(ApiCallStatus.NOT_STARTED)

  const getGradingSchemeAssignmentUsedLocations = useCallback(
    async (
      contextType: 'Account' | 'Course',
      contextId: string,
      gradingSchemeId: string,
      courseId: string,
      nextPagePath?: string,
    ): Promise<{
      assignmentUsedLocations: AssignmentUsedLocation[]
      isLastPage: boolean
      nextPage: string
    }> => {
      setGradingSchemeAssignmentUsedLocationsStatus(ApiCallStatus.PENDING)
      try {
        if (nextPagePath === undefined) {
          const contextPath = buildContextPath(contextType, contextId)
          nextPagePath = `${contextPath}/grading_schemes/${gradingSchemeId}/used_locations/${courseId}?include_archived=true`
        }

        const result = await doFetchApi({
          path: nextPagePath,
          method: 'GET',
        })
        if (!result.response.ok) {
          throw new Error(result.response.statusText)
        }

        setGradingSchemeAssignmentUsedLocationsStatus(ApiCallStatus.COMPLETED)
        return {
          // @ts-expect-error
          assignmentUsedLocations: result.json || [],
          isLastPage: result.link?.next === undefined,
          // @ts-expect-error
          nextPage: result.link?.next?.url,
        }
      } catch (err) {
        setGradingSchemeAssignmentUsedLocationsStatus(ApiCallStatus.FAILED)
        throw err
      }
    },
    [],
  )

  return {
    getGradingSchemeAssignmentUsedLocations,
    gradingSchemeAssignmentUsedLocationsStatus,
  }
}
