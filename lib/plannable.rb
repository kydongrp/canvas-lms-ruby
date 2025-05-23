# frozen_string_literal: true

#
# Copyright (C) 2017 - present Instructure, Inc.
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
#

module Plannable
  ACTIVE_WORKFLOW_STATES = ["active", "published"].freeze

  def self.included(base)
    base.class_eval do
      has_many :planner_overrides, as: :plannable
      after_save :update_associated_planner_overrides
      before_save :check_if_associated_planner_overrides_need_updating
      scope :available_to_planner, -> { where(workflow_state: ACTIVE_WORKFLOW_STATES) }
    end
  end

  def update_associated_planner_overrides_later
    delay.update_associated_planner_overrides if @associated_planner_items_need_updating != false
  end

  def update_associated_planner_overrides
    PlannerOverride.update_for(self) if @associated_planner_items_need_updating
  end

  def check_if_associated_planner_overrides_need_updating
    @associated_planner_items_need_updating = false
    return if new_record?
    return if respond_to?(:context_type) && !PlannerOverride::CONTENT_TYPES.include?(context_type)

    @associated_planner_items_need_updating = true if try(:workflow_state_changed?) || workflow_state == "deleted"
  end

  def planner_override_for(user)
    if is_a?(SubAssignment)
      return PlannerOverride.for_user(user)
                            .where(plannable_id: id, plannable_type: type)
                            .where.not(workflow_state: "deleted").take
    end

    if respond_to? :submittable_object
      submittable_override = submittable_object&.planner_override_for(user)
      return submittable_override if submittable_override
    end

    if association(:planner_overrides).loaded?
      planner_overrides.find { |po| po.user_id == user.id && po.workflow_state != "deleted" }
    else
      planner_overrides.where(user_id: user).where.not(workflow_state: "deleted").take
    end
  end

  class Bookmarker
    class Bookmark < Array
      attr_writer :descending

      def <=>(other)
        val = super
        val *= -1 if @descending
        val
      end
    end
    #   mostly copy-pasted version of SimpleBookmarker
    #   ***
    #   Now you can add some hackyness to your life by passing in an array for some sweet coalescing action
    #   as well as the ability to reverse order
    #   e.g. Plannable::Bookmarker.new(Assignment, true, [:due_at, :created_at], :id)
    #   You can also pass in a hash with the association name as the key and column name as the value
    #   to order by the joined values:
    #   e.g. Plannable::Bookmarker.new(AssessmentRequest, true, {submission: {assignment: :due_at}}, :id)

    def initialize(model, descending, *columns)
      @model = model
      @descending = !!descending
      @columns = format_columns(columns)
    end

    def format_columns(columns)
      columns.map do |col|
        col.is_a?(Array) ? col.map { |c| format_column(c) } : format_column(col)
      end
    end

    def format_column(col)
      return col if col.is_a?(Hash)

      col.to_s
    end

    # Gets the association from a hash or single nested hash to use for preloading
    # e.g. {submission: :cached_due_date} => :submission
    # or   {submission: {assignment: :due_at}} => {submission: :assignment}
    # or   {submission: {assignment: {course: id}}} => {submission: {assignment: :course}}
    def association_to_preload(col)
      result = {}
      col.each_pair do |key, value|
        return key if value.is_a?(Symbol)

        result[key] = value.is_a?(Hash) ? association_to_preload(value) : value
      end
      result
    end

    def association_value(object, col)
      rel_array = []
      rel_hash = col.clone
      while rel_hash
        rel_array << rel_hash.keys.first
        curr_val = rel_hash[rel_array.last]
        if curr_val.is_a?(Hash)
          rel_hash = curr_val
        else
          rel_array << curr_val
          rel_hash = nil
        end
      end
      rel_array.reduce(object) { |val, key| val&.send(key) }
    end

    # Grabs the value to use for the bookmark & comparison
    def column_value(object, col)
      case col
      when Array
        object.attributes.values_at(*col).compact.first # coalesce nulls
      when Hash
        association_value(object, col)
      else
        # if we used best_unicode_collation_key, the column name will be
        # something like "(attachments.display_name COLLATE \"public\".\"und-u-kn-true\")"
        col = strip_table_and_collation(col) if col.include?(@model.table_name)
        object.attributes[col]
      end
    end

    # Gets column name from a string like
    # "(attachments.display_name COLLATE \"public\".\"und-u-kn-true\")"
    def strip_table_and_collation(col)
      match = col.match(/#{Regexp.escape(@model.table_name)}\.(\w+)/)
      match ? match[1] : col
    end

    def bookmark_for(object)
      bookmark = Bookmark.new
      bookmark.descending = @descending
      # coming from users_controller, @columns looks like ["due_at", "id"]
      # coming from planner_controller, like [[:due_at, :created_at], :id]
      #   or [[{:submission=>{:assignment=>:peer_reviews_due_at}}, {:assessor_asset=>:cached_due_date}, "created_at"], "id"]
      @columns.each do |col|
        val = column_value(object, col)
        val = val.utc.strftime("%Y-%m-%d %H:%M:%S.%6N") if val.respond_to?(:strftime)
        bookmark << val
      end
      bookmark
    end

    TYPE_MAP = {
      text: ->(val) { val.is_a?(String) },
      string: ->(val) { val.is_a?(String) },
      integer: ->(val) { val.is_a?(Integer) },
      datetime: lambda do |val|
        val.is_a?(String) && Time.zone.parse(val)
      rescue ArgumentError
        false
      end
    }.freeze

    def validate(bookmark)
      bookmark.is_a?(Array) &&
        bookmark.size == @columns.size &&
        @columns.each.with_index.all? do |columns, i|
          columns = [columns] unless columns.is_a?(Array)
          columns.all? do |col|
            col = @model.columns_hash[col]
            if col
              type = TYPE_MAP[col.type]
              nullable = col.null
              type && ((nullable && bookmark[i].nil?) || type.call(bookmark[i]))
            else
              true
            end
          end
        end
    end

    def restrict_scope(scope, pager)
      if (bookmark = pager.current_bookmark)
        scope = scope.where(*comparison(bookmark))
      end
      scope.except(:order).order(order_by)
    end

    def order_by
      @order_by ||= Arel.sql(@columns.map { |col| column_order(col) }.join(", "))
    end

    # Gets the object or object's associated column name to be used in the SQL query
    def column_name(col)
      return associated_table_column_name(col) if col.is_a?(Hash)

      # if best_unicode_collation_key is used then the table name is already present
      col.include?(@model.table_name) ? col : "#{@model.table_name}.#{col}"
    end

    # Joins the associated table & column together as a string to be used in a SQL query
    def associated_table_column_name(col)
      table, column = associated_table_column(col)
      correct_table_name =
        if ActiveRecord::Base.connection.table_exists?(table.to_s)
          table.to_s
        elsif Object.const_defined?(table.to_s.classify)
          Object.const_get(table.to_s.classify).quoted_table_name
        else
          inferred_table = table.to_s.tableize
          ActiveRecord::Base.connection.table_exists?(inferred_table) ? inferred_table : table.to_s
        end
      # Return fully qualified column name
      [correct_table_name, column].join(".")
    end

    # Finds the relevant table & column name when a hash is passed by checking if
    # the hash specifies a direct or nested (i.e. the hash's value is also a hash) association
    # returns an array of [table, column]
    def associated_table_column(col)
      return col.to_s unless col.is_a?(Hash)

      col.values.first.is_a?(Hash) ? col.values.first.first : col.first
    end

    def column_order(col_name)
      if col_name.is_a?(Array)
        order = "COALESCE(#{col_name.map { |c| column_name(c) }.join(", ")})"
      else
        order = column_comparand(col_name)
        if col_type_nullable?(col_name)
          order = "#{column_comparand(col_name, "=")} IS NULL, #{order}"
        end
      end
      order += " DESC" if @descending
      order
    end

    def column_comparand(column, comparator = ">", placeholder = nil)
      col_name = placeholder ||
                 (column.is_a?(Array) ? "COALESCE(#{column.map { |c| column_name(c) }.join(", ")})" : column_name(column))
      if comparator != "=" && type_for_column(column) == :string
        col_name = BookmarkedCollection.best_unicode_collation_key(col_name)
      end
      col_name
    end

    def get_column_type(table, column)
      ActiveRecord::Base.connection.columns(table).find { |col| col.name == column.to_s }&.type
    end

    def col_type_nullable?(col)
      if col.is_a?(Hash)
        table, column = associated_table_column(col)
        correct_table_name = table.to_s.tableize
        ActiveRecord::Base.connection.columns(correct_table_name).find { |c| c.name == column.to_s }&.null
      else
        @model.columns_hash[col]&.null
      end
    end

    def column_comparison(column, comparator, value)
      if value.nil? && comparator == "="
        ["#{column_comparand(column, "=")} IS NULL"]
      elsif value.nil? && comparator == ">"
        # sorting by a nullable column puts nulls last, so for our sort order
        # 'column > NULL' is universally false
      elsif value.nil?
        # likewise only NULL values in column satisfy 'column = NULL' and
        # 'column >= NULL'
        ["#{column_comparand(column, "=")} IS NOT NULL"]
      else
        column_type = if column.is_a?(Hash)
                        table, col = associated_table_column(column)
                        correct_table_name = table.to_s.tableize
                        get_column_type(correct_table_name, col)
                      else
                        @model.columns_hash[column]&.type
                      end
        # 🚀 Ensure value is cast correctly before comparison
        if column_type == :string && value.is_a?(Integer)
          value = value.to_s
        elsif column_type == :integer && value.is_a?(String)
          value = value.to_i
        end

        sql = "#{column_comparand(column, comparator)} #{comparator} #{column_comparand(column, comparator, "?")}"
        if !column.is_a?(Array) && col_type_nullable?(column) && comparator != "="
          # our sort order wants "NULL > ?" to be universally true for non-NULL
          # values (we already handle NULL values above). but it is false in
          # SQL, so we need to include "column IS NULL" with > or >=
          sql = "(#{sql} OR #{column_comparand(column, "=")} IS NULL)"
        end
        [sql, value]
      end
    end

    def type_for_column(col)
      col = col.first if col.is_a?(Array)
      @model.columns_hash[col]&.type
    end

    # Generate a sql comparison like so:
    #
    #   a > ?
    #   OR a = ? AND b > ?
    #   OR a = ? AND b = ? AND c > ?
    #
    # Technically there's an extra check in the actual result (for index
    # happiness), but it's logically equivalent to the example above
    def comparison(bookmark)
      top_clauses = []
      args = []
      visited = []
      pairs = @columns.zip(bookmark)
      comparator = @descending ? "<" : ">"
      while pairs.present?
        col, val = pairs.shift
        clauses = []
        visited.each do |c, v|
          clause, *clause_args = column_comparison(c, "=", v)
          clauses << clause
          args.concat(clause_args)
        end
        clause, *clause_args = column_comparison(col, comparator, val)
        clauses << clause
        clauses.compact!
        top_clauses << clauses.join(" AND ") if clauses.present?
        args.concat(clause_args)
        visited << [col, val]
      end
      sql = "(" + top_clauses.join(" OR ") + ")"
      [sql, *args]
    end
  end
end
