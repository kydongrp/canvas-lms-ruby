/*
 * Copyright (C) 2015 - present Instructure, Inc.
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

import React, {useMemo} from 'react'
import {Flex} from '@instructure/ui-flex'
import {View} from '@instructure/ui-view'
import {Badge} from '@instructure/ui-badge'
import {Avatar} from '@instructure/ui-avatar'
import {Text} from '@instructure/ui-text'
import {List} from '@instructure/ui-list'
import {Heading} from '@instructure/ui-heading'
import {IconButton} from '@instructure/ui-buttons'
import {ToggleDetails} from '@instructure/ui-toggle-details'
import {
  IconAdminLine,
  IconCalendarMonthLine,
  IconClockLine,
  IconCoursesLine,
  IconDashboardLine,
  IconExternalLinkLine,
  IconGroupLine,
  IconHomeLine,
  IconInboxLine,
  IconLockLine,
  IconQuestionLine,
  IconXLine,
} from '@instructure/ui-icons'
import {useScope as createI18nScope} from '@canvas/i18n'
import HelpDialog from '@canvas/help-dialog'
import {Link} from '@instructure/ui-link'
import CoursesList from './lists/CoursesList'
import GroupsList from './lists/GroupsList'
import AccountsList from './lists/AccountsList'
import ProfileTabsList from './lists/ProfileTabsList'
import HistoryList from './lists/HistoryList'
import {getUnreadCount} from './queries/unreadCountQuery'
import {filterAndProcessTools, getExternalApps, type ProcessedTool} from './utils'
import {SVGIcon} from '@instructure/ui-svg-images'
import {Img} from '@instructure/ui-img'
import {useQuery} from '@tanstack/react-query'
import {sessionStoragePersister} from '@canvas/query'

const I18n = createI18nScope('MobileGlobalMenu')

type Props = {
  onDismiss: () => void
}

export default function MobileGlobalMenu(props: Props) {
  const showGroups = useMemo(() => Boolean(document.getElementById('global_nav_groups_link')), [])
  const countsEnabled = Boolean(
    window.ENV.current_user_id && !window.ENV.current_user?.fake_student,
  )
  const k5User = window.ENV.K5_USER
  const showAdmin =
    window.ENV.current_user_is_admin ||
    (window.ENV.current_user_roles && window.ENV.current_user_roles.includes('admin'))
  const current_user: {
    display_name: string
    avatar_image_url: string
  } = window.ENV.current_user

  const {data: externalToolsData} = useQuery({
    queryKey: ['external_tools'],
    queryFn: getExternalApps,
    staleTime: 2 * 60 * 1000, // two minutes,
    enabled: true,
    persister: sessionStoragePersister,
  })
  const processedTools = useMemo(
    () => filterAndProcessTools(externalToolsData || []),
    [externalToolsData],
  )

  const {data: unreadConversationsCount, isSuccess: unreadConversationsCountHasLoaded} = useQuery({
    queryKey: ['unread_count', 'conversations'],
    queryFn: getUnreadCount,
    staleTime: 2 * 60 * 1000, // two minutes
    enabled: countsEnabled && !ENV.current_user_disabled_inbox,
    persister: sessionStoragePersister,
  })

  return (
    <View
      display="block"
      height="100%"
      width="100%"
      textAlign="start"
      padding="medium large medium medium"
    >
      <Flex direction="row-reverse" margin="0 0 large 0">
        <Flex.Item>
          <IconButton
            renderIcon={IconXLine}
            withBackground={false}
            withBorder={false}
            onClick={props.onDismiss}
            screenReaderLabel="Close"
          />
        </Flex.Item>
        <Flex.Item shouldGrow={true} shouldShrink={true}>
          <Heading>
            <a className="ic-brand-mobile-global-nav-logo" href="/">
              <span className="screenreader-only">
                {k5User ? I18n.t('Home') : I18n.t('My Dashboard')}
              </span>
            </a>
          </Heading>
        </Flex.Item>
      </Flex>
      <List isUnstyled={true} itemSpacing="medium">
        <List.Item>
          <Link href="/" isWithinText={false} display="block">
            <Flex>
              <Flex.Item width="3rem">
                {k5User ? (
                  <IconHomeLine inline={false} size="small" />
                ) : (
                  <IconDashboardLine inline={false} size="small" />
                )}
              </Flex.Item>
              <Flex.Item>
                <Text size="medium">{k5User ? I18n.t('Home') : I18n.t('Dashboard')}</Text>
              </Flex.Item>
            </Flex>
          </Link>
        </List.Item>

        <List.Item>
          {current_user && Object.keys(current_user).length > 0 ? (
            <ToggleDetails
              iconPosition="end"
              fluidWidth={true}
              summary={
                <Flex>
                  <Flex.Item width="3rem">
                    <Avatar
                      name={current_user.display_name}
                      src={current_user.avatar_image_url}
                      size="x-small"
                      data-fs-exclude={true}
                    />
                  </Flex.Item>
                  <Flex.Item>
                    <Text color="brand">{I18n.t('Account')}</Text>
                  </Flex.Item>
                </Flex>
              }
            >
              <ProfileTabsList />
            </ToggleDetails>
          ) : (
            <Link href="/login" isWithinText={false} display="block">
              <Flex>
                <Flex.Item width="3rem">
                  <IconLockLine inline={false} size="small" />
                </Flex.Item>
                <Flex.Item>
                  <Text size="medium">{I18n.t('Login')}</Text>
                </Flex.Item>
              </Flex>
            </Link>
          )}
        </List.Item>

        {showAdmin && (
          <List.Item>
            <ToggleDetails
              iconPosition="end"
              fluidWidth={true}
              summary={
                <Flex>
                  <Flex.Item width="3rem">
                    <IconAdminLine inline={false} size="small" color="brand" />
                  </Flex.Item>
                  <Flex.Item>
                    <Text color="brand">{I18n.t('Admin')}</Text>
                  </Flex.Item>
                </Flex>
              }
            >
              <AccountsList />
            </ToggleDetails>
          </List.Item>
        )}

        <List.Item>
          <ToggleDetails
            iconPosition="end"
            fluidWidth={true}
            summary={
              <Flex>
                <Flex.Item width="3rem">
                  <IconCoursesLine inline={false} size="small" color="brand" />
                </Flex.Item>
                <Flex.Item>
                  <Text color="brand">{k5User ? I18n.t('Subjects') : I18n.t('Courses')}</Text>
                </Flex.Item>
              </Flex>
            }
          >
            <CoursesList />
          </ToggleDetails>
        </List.Item>

        {showGroups && (
          <List.Item>
            <ToggleDetails
              iconPosition="end"
              fluidWidth={true}
              summary={
                <Flex>
                  <Flex.Item width="3rem">
                    <IconGroupLine inline={false} size="small" color="brand" />
                  </Flex.Item>
                  <Flex.Item>
                    <Text color="brand">{I18n.t('Groups')}</Text>
                  </Flex.Item>
                </Flex>
              }
            >
              <GroupsList />
            </ToggleDetails>
          </List.Item>
        )}

        <List.Item>
          <Link href="/calendar" isWithinText={false} display="block">
            <Flex>
              <Flex.Item width="3rem">
                <IconCalendarMonthLine inline={false} size="small" />
              </Flex.Item>
              <Flex.Item>
                <Text size="medium">{I18n.t('Calendar')}</Text>
              </Flex.Item>
            </Flex>
          </Link>
        </List.Item>

        <List.Item>
          <Link href="/inbox" isWithinText={false} display="block">
            <Flex>
              <Flex.Item width="3rem">
                <IconInboxLine inline={false} size="small" />
              </Flex.Item>
              <Flex.Item>
                <Text size="medium">{I18n.t('Inbox')}</Text>
                {unreadConversationsCountHasLoaded && unreadConversationsCount > 0 && (
                  <Badge standalone={true} margin="0 small" count={unreadConversationsCount} />
                )}
              </Flex.Item>
            </Flex>
          </Link>
        </List.Item>

        {processedTools.map((tool: ProcessedTool) => (
          <List.Item key={tool.toolId}>
            <Link href={tool.href || '#'} isWithinText={false} display="block">
              <Flex>
                <Flex.Item width="3rem">
                  {tool.svgPath ? (
                    <SVGIcon
                      size="small"
                      viewBox="0 0 64 64"
                      title="svg-external-tool"
                      color="auto"
                    >
                      <path d={tool.svgPath} />
                    </SVGIcon>
                  ) : tool.toolImg ? (
                    <Img width="26px" height="26px" src={tool.toolImg} alt="" />
                  ) : (
                    <IconExternalLinkLine data-testid="IconExternalLinkLine" size="small" />
                  )}
                </Flex.Item>
                <Flex.Item>
                  <Text size="medium">{tool.label}</Text>
                </Flex.Item>
              </Flex>
            </Link>
          </List.Item>
        ))}

        <List.Item>
          <ToggleDetails
            iconPosition="end"
            fluidWidth={true}
            summary={
              <Flex>
                <Flex.Item width="3rem">
                  <IconClockLine inline={false} size="small" color="brand" />
                </Flex.Item>
                <Flex.Item>
                  <Text color="brand">{I18n.t('History')}</Text>
                </Flex.Item>
              </Flex>
            }
          >
            <View as="div" margin="0 0 0 xx-large">
              <HistoryList />
            </View>
          </ToggleDetails>
        </List.Item>

        <List.Item>
          <ToggleDetails
            iconPosition="end"
            fluidWidth={true}
            summary={
              <Flex>
                <Flex.Item width="3rem">
                  <IconQuestionLine inline={false} size="small" color="brand" />
                </Flex.Item>
                <Flex.Item>
                  <Text color="brand">{window.ENV.help_link_name || I18n.t('Help')}</Text>
                </Flex.Item>
              </Flex>
            }
          >
            <View as="div" margin="0 0 0 xx-large">
              <HelpDialog onFormSubmit={props.onDismiss} />
            </View>
          </ToggleDetails>
        </List.Item>
      </List>
    </View>
  )
}
