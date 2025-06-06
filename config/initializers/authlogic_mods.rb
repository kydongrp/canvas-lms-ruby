# frozen_string_literal: true

#
# Copyright (C) 2011 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

callback_chain = Authlogic::Session::Base._persist_callbacks
# We need the session cookie to take precendence over the "remember me" cookie,
# otherwise we'll use the "remember me" cookie every request, which triggers
# generating a new "remember me" cookie since they're one-time use.
cb = callback_chain.delete(callback_chain.find { |cb2| cb2.filter == :persist_by_cookie })
callback_chain.append(cb) if cb

# be tolerant of using a secondary
module IgnoreSlaveErrors
  def save_record(alternate_record = nil)
    super
  rescue ActiveRecord::StatementInvalid => e
    # "simulated" secondary of a user with read-only access; probably the same error for Slony
    raise if !e.message.match(/PG(?:::)?Error: ERROR: +permission denied for relation/) &&
             # real secondary that's in recovery
             !e.message.match(/PG(?:::)?Error: ERROR: +cannot execute UPDATE in a read-only transaction/)
  end
end
Authlogic::Session::Base.prepend(IgnoreSlaveErrors)
