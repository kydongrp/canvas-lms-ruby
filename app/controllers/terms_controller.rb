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
#

# @API Enrollment Terms
class TermsController < ApplicationController
  before_action :require_context, :require_root_account_management
  include Api::V1::EnrollmentTerm

  def permitted_enrollment_term_attributes
    %i[name start_at end_at]
  end

  # @API Create enrollment term
  #
  # Create a new enrollment term for the specified account.
  #
  # @argument enrollment_term[name] [String]
  #   The name of the term.
  #
  # @argument enrollment_term[start_at] [DateTime]
  #   The day/time the term starts.
  #   Accepts times in ISO 8601 format, e.g. 2015-01-10T18:48:00Z.
  #
  # @argument enrollment_term[end_at] [DateTime]
  #   The day/time the term ends.
  #   Accepts times in ISO 8601 format, e.g. 2015-01-10T18:48:00Z.
  #
  # @argument enrollment_term[sis_term_id] [String]
  #   The unique SIS identifier for the term.
  #
  # @argument enrollment_term[overrides][enrollment_type][start_at] [DateTime]
  #   The day/time the term starts, overridden for the given enrollment type.
  #   *enrollment_type* can be one of StudentEnrollment, TeacherEnrollment, TaEnrollment, or DesignerEnrollment
  #
  # @argument enrollment_term[overrides][enrollment_type][end_at] [DateTime]
  #   The day/time the term ends, overridden for the given enrollment type.
  #   *enrollment_type* can be one of StudentEnrollment, TeacherEnrollment, TaEnrollment, or DesignerEnrollment
  #
  # @returns EnrollmentTerm
  #
  def create
    @term = @context.enrollment_terms.active.build
    save_and_render_response
  end

  # @API Update enrollment term
  #
  # Update an existing enrollment term for the specified account.
  #
  # @argument enrollment_term[name] [String]
  #   The name of the term.
  #
  # @argument enrollment_term[start_at] [DateTime]
  #   The day/time the term starts.
  #   Accepts times in ISO 8601 format, e.g. 2015-01-10T18:48:00Z.
  #
  # @argument enrollment_term[end_at] [DateTime]
  #   The day/time the term ends.
  #   Accepts times in ISO 8601 format, e.g. 2015-01-10T18:48:00Z.
  #
  # @argument enrollment_term[sis_term_id] [String]
  #   The unique SIS identifier for the term.
  #
  # @argument enrollment_term[overrides][enrollment_type][start_at] [DateTime]
  #   The day/time the term starts, overridden for the given enrollment type.
  #   *enrollment_type* can be one of StudentEnrollment, TeacherEnrollment, TaEnrollment, or DesignerEnrollment
  #
  # @argument enrollment_term[overrides][enrollment_type][end_at] [DateTime]
  #   The day/time the term ends, overridden for the given enrollment type.
  #   *enrollment_type* can be one of StudentEnrollment, TeacherEnrollment, TaEnrollment, or DesignerEnrollment
  #
  # @argument override_sis_stickiness [boolean]
  #   Default is true. If false, any fields containing “sticky” changes will not be updated.
  #   See SIS CSV Format documentation for information on which fields can have SIS stickiness
  #
  # @returns EnrollmentTerm
  #
  def update
    @term = api_find(@context.enrollment_terms.active, params[:id])
    save_and_render_response
  end

  # @API Delete enrollment term
  #
  # Delete the specified enrollment term.
  #
  # @returns EnrollmentTerm
  #
  def destroy
    @term = api_find(@context.enrollment_terms, params[:id])
    @term.workflow_state = "deleted"

    if @term.save
      if api_request?
        render json: enrollment_term_json(@term, @current_user, session)
      else
        render json: @term
      end
    else
      render json: @term.errors, status: :bad_request
    end
  end

  private

  def save_and_render_response
    params.require(:enrollment_term)
    overrides = params[:enrollment_term][:overrides]&.to_unsafe_h
    if overrides.present? && !(overrides.keys.map(&:classify) - %w[StudentEnrollment TeacherEnrollment TaEnrollment DesignerEnrollment]).empty?
      return render json: { message: "Invalid enrollment type in overrides" }, status: :bad_request
    end

    sis_id = params[:enrollment_term][:sis_source_id] || params[:enrollment_term][:sis_term_id]
    if sis_id && !(sis_id.is_a?(String) || sis_id.is_a?(Numeric))
      return render json: { message: "Invalid SIS ID" }, status: :bad_request
    end

    handle_sis_id_param(sis_id)

    term_params = if request.request_method.downcase == "put" && params[:override_sis_stickiness] && !value_to_boolean(params[:override_sis_stickiness])
                    params.require(:enrollment_term).permit(*(permitted_enrollment_term_attributes - @term.stuck_sis_fields.to_a))
                  else
                    params.require(:enrollment_term).permit(*permitted_enrollment_term_attributes)
                  end

    SubmissionLifecycleManager.with_executing_user(@current_user) do
      if validate_dates(@term, term_params, overrides) && @term.update(term_params)
        @term.set_overrides(@context, overrides)
        # Republish any courses with course paces that may be affected
        if @term.saved_changes.keys.intersect?(%w[start_at end_at])
          @term.courses.where("restrict_enrollments_to_course_dates IS NOT TRUE AND settings LIKE ?", "%enable_course_paces: true%").find_each do |course|
            course.course_paces.find_each(&:create_publish_progress)
          end
        end
        render json: serialized_term
      else
        render json: @term.errors, status: :bad_request
      end
    end
  end

  def validate_dates(term, term_params, overrides)
    hashes = [term_params]
    hashes += overrides.values if overrides
    invalid_dates = hashes.any? do |hash|
      start_at = Time.zone.parse(hash[:start_at]) if hash[:start_at]
      end_at = Time.zone.parse(hash[:end_at]) if hash[:end_at]
      start_at && end_at && end_at < start_at
    rescue ArgumentError
      false
    end
    term.errors.add(:base, t("End dates cannot be before start dates")) if invalid_dates
    !invalid_dates
  end

  def handle_sis_id_param(sis_id)
    if !sis_id.nil? &&
       sis_id != @account.sis_source_id &&
       @context.root_account.grants_right?(@current_user, session, :manage_sis)
      @term.sis_source_id = sis_id.presence
      if @term.sis_source_id && @term.sis_source_id_changed?
        scope = @term.root_account.enrollment_terms.where(sis_source_id: @term.sis_source_id)
        scope = scope.where("id<>?", @term) unless @term.new_record?
        @term.errors.add(:sis_source_id, t("errors.not_unique", "SIS ID \"%{sis_source_id}\" is already in use", sis_source_id: @term.sis_source_id)) if scope.exists?
      end
    end
  end

  def serialized_term
    if api_request?
      enrollment_term_json(@term, @current_user, session, nil, ["overrides"])
    else
      @term.as_json(include: :enrollment_dates_overrides, methods: :filter_courses_by_term)
    end
  end
end
