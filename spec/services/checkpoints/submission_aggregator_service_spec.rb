# frozen_string_literal: true

#
# Copyright (C) 2023 - present Instructure, Inc.
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

describe Checkpoints::SubmissionAggregatorService do
  describe ".call" do
    before(:once) do
      @course = course_model
      @course.account.enable_feature!(:discussion_checkpoints)
      @student = student_in_course(course: @course, active_all: true).user
      @topic = DiscussionTopic.create_graded_topic!(course: @course, title: "graded topic")
      @topic.create_checkpoints(reply_to_topic_points: 3, reply_to_entry_points: 7)
    end

    let(:service) { Checkpoints::SubmissionAggregatorService }
    let(:service_call) { service.call(assignment: @topic.assignment, student: @student) }
    let(:submission) { @topic.assignment.submissions.find_by(user: @student) }
    let(:sub_assignment_submissions) { @topic.assignment.sub_assignment_submissions.where(user: @student) }

    describe "invalid states" do
      it "returns false when called with an assignment that is not checkpointed" do
        assignment = @course.assignments.create!
        expect(service.call(assignment:, student: @student)).to be false
      end

      it "returns false when called with a 'child' (checkpoint) assignment" do
        assignment = @topic.sub_assignments.first
        expect(service.call(assignment:, student: @student)).to be false
      end

      it "returns false when called with a soft-deleted checkpointed assignment" do
        @topic.assignment.destroy
        expect(service_call).to be false
      end

      it "returns false when checkpoint discussions are disabled" do
        @course.account.disable_feature!(:discussion_checkpoints)
        expect(service_call).to be false
      end

      it "returns false when the given user is not assigned" do
        expect(service.call(assignment: @topic.assignment, student: @teacher)).to be false
      end
    end

    describe "score" do
      it "creates a parent submission when none exists and correctly aggregates a single checkpoint score" do
        @course2 = course_model
        assignment_without_submissions = @course2.assignments.create!(title: "My Assignment")
        assignment_without_submissions.sub_assignments.create!(title: "sub assignment", context: assignment_without_submissions.context, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
        assignment_without_submissions.reload
        enrollment_params = { enrollment_state: "active", type: "StudentEnrollment", return_type: :record }
        create_enrollments(@course2, [@student], enrollment_params)

        expect(assignment_without_submissions.submissions.find_by(user: @student)).to be_nil
        # grade only the REPLY_TO_TOPIC checkpoint
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          assignment_without_submissions.grade_student(
            @student,
            grader: @teacher,
            score: 5,
            sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC
          )
        end
        result = nil
        expect do
          result = service.call(assignment: assignment_without_submissions, student: @student)
        end.to change { assignment_without_submissions.submissions.count }.from(0).to(1)
        expect(result).to be true

        # verify both child and parent scores
        child  = assignment_without_submissions.sub_assignments.first.submissions.first
        parent = assignment_without_submissions.submissions.first

        expect(child.score).to eq 5
        expect(parent.score).to eq 5
      end

      it "saves the sum of checkpoint scores on the parent submission" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
        end

        success = service_call
        expect(success).to be true
        expect(submission.score).to eq 10
      end

      it "handles all checkpoints having no score" do
        success = service_call
        expect(success).to be true
        expect(submission.score).to be_nil
      end

      it "handles the first checkpoint having no score" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
        end

        success = service_call
        expect(success).to be true
        expect(submission.score).to eq 7
      end

      it "handles the second checkpoint having no score" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
        end

        success = service_call
        expect(success).to be true
        expect(submission.score).to eq 3
      end

      it "ignores excused submissions" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          @topic.assignment.grade_student(@student, grader: @teacher, excused: true, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
        end

        success = service_call
        expect(success).to be true
        expect(submission.score).to eq 7
      end
    end

    describe "published_score" do
      it "saves the sum of checkpoint published_scores on the parent submission" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
        end

        success = service_call
        expect(success).to be true
        expect(submission.published_score).to eq 10
      end

      it "handles all checkpoints having no published_score" do
        success = service_call
        expect(success).to be true
        expect(submission.published_score).to be_nil
      end

      it "handles the first checkpoint having no published_score" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
        end

        success = service_call
        expect(success).to be true
        expect(submission.published_score).to eq 7
      end

      it "handles the second checkpoint having no published_score" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
        end

        success = service_call
        expect(success).to be true
        expect(submission.published_score).to eq 3
      end

      it "ignores excused submissions" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          @topic.assignment.grade_student(@student, grader: @teacher, excused: true, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
        end

        success = service_call
        expect(success).to be true
        expect(submission.published_score).to eq 7
      end
    end

    describe "updated_at" do
      it "saves the most recent checkpoint updated_at on the parent submission" do
        now = Time.zone.now
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          Timecop.freeze(5.minutes.ago(now)) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          end

          Timecop.freeze(now) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
          end
        end

        success = service_call
        expect(success).to be true
        expect(submission.updated_at).to eq now
      end

      it "handles all checkpoints not having an updated_at" do
        Submission.update_all(updated_at: nil)
        success = service_call
        expect(success).to be true
        expect(submission.updated_at).to be_nil
      end

      it "handles the first checkpoint not having an updated_at" do
        now = Time.zone.now
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          Timecop.freeze(now) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
            @topic.reply_to_topic_checkpoint.submissions.find_by(user: @student).update_columns(updated_at: nil)
          end
        end
        success = service_call
        expect(success).to be true
        expect(submission.updated_at).to eq now
      end

      it "handles the second checkpoint not having an updated_at" do
        now = Time.zone.now
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          Timecop.freeze(now) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
            @topic.reply_to_entry_checkpoint.submissions.find_by(user: @student).update_columns(updated_at: nil)
          end
        end
        success = service_call
        expect(success).to be true
        expect(submission.updated_at).to eq now
      end
    end

    describe "grade" do
      context "when the grade is displayed as points" do
        before(:once) do
          @topic.assignment.update!(grading_type: "points")
        end

        it "sets the grade to the stringified version of the aggregate score" do
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
            @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
          end

          success = service_call
          expect(success).to be true
          expect(submission.grade).to eq "10"
        end

        it "works when neither checkpoint has a score" do
          success = service_call
          expect(success).to be true
          expect(submission.grade).to be_nil
        end

        it "works when one checkpoint has no score" do
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          end

          success = service_call
          expect(success).to be true
          expect(submission.grade).to eq "3"
        end

        context "pass_fail" do
          before(:once) do
            @topic.assignment.update!(grading_type: "pass_fail")
            @topic.assignment.sub_assignments.find_by(sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC).update!(grading_type: "pass_fail")
            @topic.assignment.sub_assignments.find_by(sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY).update!(grading_type: "pass_fail")
          end

          it "sets the grade to 'complete' when both checkpoints are complete" do
            Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
              @topic.assignment.grade_student(@student, grader: @teacher, grade: "complete", sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
              @topic.assignment.grade_student(@student, grader: @teacher, grade: "complete", sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
            end

            success = service_call
            expect(success).to be true
            expect(submission.grade).to eq "complete"
          end

          it "sets the grade to 'incomplete' when the second checkpoint is incomplete" do
            Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
              @topic.assignment.grade_student(@student, grader: @teacher, grade: "complete", sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
              @topic.assignment.grade_student(@student, grader: @teacher, grade: "incomplete", sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
            end

            success = service_call
            expect(success).to be true
            expect(submission.grade).to eq "incomplete"
          end

          it "sets the grade to 'incomplete' when the first checkpoint is incomplete" do
            Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
              @topic.assignment.grade_student(@student, grader: @teacher, grade: "incomplete", sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
              @topic.assignment.grade_student(@student, grader: @teacher, grade: "complete", sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
            end

            success = service_call
            expect(success).to be true
            expect(submission.grade).to eq "incomplete"
          end

          it "sets the grade to nil when both checkpoints are nil" do
            success = service_call
            expect(success).to be true
            expect(submission.grade).to be_nil
          end
        end
      end

      context "when the grade is displayed as letter grade" do
        before(:once) do
          @topic.assignment.update!(grading_type: "letter_grade")
        end

        it "sets the grade to the letter grade associated with the aggregate score" do
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
            @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
          end

          success = service_call
          expect(success).to be true
          expect(submission.grade).to eq "A"
        end

        it "works when neither checkpoint has a score" do
          success = service_call
          expect(success).to be true
          expect(submission.grade).to be_nil
        end

        it "works when one checkpoint has no score" do
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          end

          success = service_call
          expect(success).to be true
          expect(submission.grade).to eq "F"
        end
      end
    end

    describe "published_grade" do
      context "when the grade is displayed as points" do
        before(:once) do
          @topic.assignment.update!(grading_type: "points")
        end

        it "sets the grade to the stringified version of the aggregate published_score" do
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
            @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
          end

          success = service_call
          expect(success).to be true
          expect(submission.published_grade).to eq "10"
        end

        it "works when neither checkpoint has a published_score" do
          success = service_call
          expect(success).to be true
          expect(submission.published_grade).to be_nil
        end

        it "works when one checkpoint has no published_score" do
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          end

          success = service_call
          expect(success).to be true
          expect(submission.published_grade).to eq "3"
        end
      end

      context "when the grade is displayed as letter grade" do
        before(:once) do
          @topic.assignment.update!(grading_type: "letter_grade")
        end

        it "sets the grade to the letter grade associated with the aggregate published_score" do
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
            @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
          end

          success = service_call
          expect(success).to be true
          expect(submission.published_grade).to eq "A"
        end

        it "works when neither checkpoint has a published_score" do
          success = service_call
          expect(success).to be true
          expect(submission.published_grade).to be_nil
        end

        it "works when one checkpoint has no published_score" do
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          end

          success = service_call
          expect(success).to be true
          expect(submission.published_grade).to eq "F"
        end
      end
    end

    describe "grader related fields" do
      before(:once) do
        @earliest_grader = @teacher
        @most_recent_grader = teacher_in_course(course: @course, active_all: true).user
      end

      describe "grader_id" do
        it "sets the grader_id to the most recent grader" do
          now = Time.zone.now
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            Timecop.freeze(5.minutes.ago(now)) do
              @topic.assignment.grade_student(@student, grader: @earliest_grader, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
            end

            Timecop.freeze(now) do
              @topic.assignment.grade_student(@student, grader: @most_recent_grader, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
            end
          end

          success = service_call
          expect(success).to be true
          expect(submission.grader_id).to eq @most_recent_grader.id
        end

        it "works when neither checkpoint is graded" do
          success = service_call
          expect(success).to be true
          expect(submission.grader_id).to be_nil
        end

        it "works when one checkpoint is not graded" do
          now = Time.zone.now
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            Timecop.freeze(now) do
              @topic.assignment.grade_student(@student, grader: @most_recent_grader, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
            end
          end

          success = service_call
          expect(success).to be true
          expect(submission.grader_id).to eq @most_recent_grader.id
        end
      end

      describe "graded_at" do
        it "sets the graded_at to the timestamp from the most recent grading event" do
          now = Time.zone.now
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            Timecop.freeze(5.minutes.ago(now)) do
              @topic.assignment.grade_student(@student, grader: @earliest_grader, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
            end

            Timecop.freeze(now) do
              @topic.assignment.grade_student(@student, grader: @most_recent_grader, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
            end
          end

          success = service_call
          expect(success).to be true
          expect(submission.graded_at).to eq now
        end

        it "works when neither checkpoint is graded" do
          success = service_call
          expect(success).to be true
          expect(submission.graded_at).to be_nil
        end

        it "works when one checkpoint is not graded" do
          now = Time.zone.now
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            Timecop.freeze(now) do
              @topic.assignment.grade_student(@student, grader: @most_recent_grader, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
            end
          end

          success = service_call
          expect(success).to be true
          expect(submission.graded_at).to eq now
        end
      end

      describe "graded_anonymously" do
        it "sets graded_anonymously to the value stored on the most recently graded submission" do
          now = Time.zone.now
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            Timecop.freeze(5.minutes.ago(now)) do
              @topic.assignment.grade_student(
                @student,
                grader: @earliest_grader,
                graded_anonymously: true,
                score: 3,
                sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC
              )
            end

            Timecop.freeze(now) do
              @topic.assignment.grade_student(
                @student,
                grader: @most_recent_grader,
                graded_anonymously: false,
                score: 7,
                sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY
              )
            end
          end

          success = service_call
          expect(success).to be true
          expect(submission.graded_anonymously).to be false
        end

        it "works when neither checkpoint is graded (leaving graded_anonymously as nil, the default)" do
          success = service_call
          expect(success).to be true
          expect(submission.graded_anonymously).to be_nil
        end

        it "works when one checkpoint is not graded" do
          now = Time.zone.now
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            Timecop.freeze(now) do
              @topic.assignment.grade_student(
                @student,
                grader: @most_recent_grader,
                graded_anonymously: true,
                score: 7,
                sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY
              )
            end
          end

          success = service_call
          expect(success).to be true
          expect(submission.graded_anonymously).to be true
        end
      end

      describe "grade_matches_current_submission" do
        it "sets grade_matches_current_submission to false when any checkpoint's grade does not match the current submission" do
          now = Time.zone.now
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            Timecop.freeze(10.minutes.ago(now)) do
              @topic.assignment.grade_student(
                @student,
                grader: @earliest_grader,
                score: 3,
                sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC
              )
            end

            Timecop.freeze(5.minutes.ago(now)) do
              @topic.reply_to_topic_checkpoint.submit_homework(@student, submission_type: "discussion_topic")
            end

            Timecop.freeze(3.minutes.ago(now)) do
              @topic.reply_to_entry_checkpoint.submit_homework(@student, submission_type: "discussion_topic")
            end

            Timecop.freeze(now) do
              @topic.assignment.grade_student(
                @student,
                grader: @most_recent_grader,
                score: 7,
                sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY
              )
            end
          end

          success = service_call
          expect(success).to be true
          expect(submission.grade_matches_current_submission).to be false
        end

        it "sets grade_matches_current_submission to true when all checkpoints' grades match the current submission" do
          now = Time.zone.now
          Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
            Timecop.freeze(5.minutes.ago(now)) do
              @topic.reply_to_topic_checkpoint.submit_homework(@student, submission_type: "discussion_topic")
            end

            Timecop.freeze(4.minutes.ago(now)) do
              @topic.assignment.grade_student(
                @student,
                grader: @earliest_grader,
                score: 3,
                sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC
              )
            end

            Timecop.freeze(3.minutes.ago(now)) do
              @topic.reply_to_entry_checkpoint.submit_homework(@student, submission_type: "discussion_topic")
            end

            Timecop.freeze(now) do
              @topic.assignment.grade_student(
                @student,
                grader: @most_recent_grader,
                score: 7,
                sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY
              )
            end
          end

          success = service_call
          expect(success).to be true
          expect(submission.grade_matches_current_submission).to be true
        end

        it "works when neither checkpoint is graded or submitted to (leaving grade_matches_current_submission as nil, the default)" do
          success = service_call
          expect(success).to be true
          expect(submission.grade_matches_current_submission).to be_nil
        end

        it "works when a checkpoint has been submitted to, but none have been graded" do
          @topic.reply_to_topic_checkpoint.submit_homework(@student, submission_type: "discussion_topic")
          success = service_call
          expect(success).to be true
          # the "grade" is considered to "match the current submission" when a
          # student has turned in work but has not been graded
          expect(submission.grade_matches_current_submission).to be true
        end
      end
    end

    describe "posted_at" do
      it "is set to the most-recently posted checkpoint's timestamp when both checkpoints have been posted" do
        now = Time.zone.now
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          # grading a student automatically posts their submission when the assignment is set to automatically post
          Timecop.freeze(5.minutes.ago(now)) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          end

          Timecop.freeze(now) do
            @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
          end
        end

        success = service_call
        expect(success).to be true
        expect(submission.posted_at).to eq now
      end

      it "is nil when one checkpoint is posted and the other is not" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          # grading a student automatically posts their submission when the assignment is set to automatically post
          @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
        end

        success = service_call
        expect(success).to be true
        expect(submission.posted_at).to be_nil
      end

      it "is nil when neither checkpoint is posted" do
        success = service_call
        expect(success).to be true
        expect(submission.posted_at).to be_nil
      end
    end

    describe "workflow_state" do
      it "sets the workflow_state to the workflow_state of checkpoints when they match" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.assignment.grade_student(@student, grader: @teacher, score: 3, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          @topic.assignment.grade_student(@student, grader: @teacher, score: 7, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
        end

        success = service_call
        expect(success).to be true
        expect(submission.workflow_state).to eq "graded"
      end

      it "sets the workflow_state to 'unsubmitted' when checkpoint states don't match" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.reply_to_topic_checkpoint.submit_homework(@student, submission_type: "discussion_topic")
        end

        success = service_call
        expect(success).to be true
        expect(submission.workflow_state).to eq "unsubmitted"
      end
    end

    describe "excused" do
      it "sets excused to true when both checkpoints are excused" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.assignment.grade_student(@student, grader: @teacher, excused: true, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          @topic.assignment.grade_student(@student, grader: @teacher, excused: true, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
        end

        success = service_call
        expect(success).to be true
        expect(submission.excused).to be true
      end

      it "sets excused to true when only one checkpoint is excused" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.assignment.grade_student(@student, grader: @teacher, score: 5, sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
          @topic.assignment.grade_student(@student, grader: @teacher, excused: true, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
        end

        success = service_call
        expect(success).to be true
        expect(submission.excused).to be true
      end

      it "sets excused to true when one checkpoint is excused and the other is ungraded" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.assignment.grade_student(@student, grader: @teacher, excused: true, sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
        end

        success = service_call
        expect(success).to be true
        expect(submission.excused).to be true
      end
    end

    describe "grading_period_id" do
      before :once do
        gpg = GradingPeriodGroup.create! title: "asdf",
                                         root_account: @course.root_account
        @course.enrollment_term.update grading_period_group: gpg
        @term1 = gpg.grading_periods.create! title: "past grading period",
                                             start_date: 2.weeks.ago,
                                             end_date: 1.week.ago
        @term2 = gpg.grading_periods.create! title: "current grading period",
                                             start_date: 2.days.ago,
                                             end_date: 2.days.from_now
      end

      it "sets the grading_period_id to the grading_period_id shared by both checkpoints" do
        submission.grading_period_id = nil
        submission.save!

        # before running the service, make sure checkpoint submissions are still in @term2
        expect(sub_assignment_submissions.first.grading_period_id).to eq @term2.id
        expect(sub_assignment_submissions.last.grading_period_id).to eq @term2.id

        success = service_call
        expect(success).to be true
        expect(submission.reload.grading_period_id).to eq @term2.id
      end

      it "sets the grading_period_id to nil when checkpoints are in different grading periods" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          sub_assignment_submissions.first.update!(grading_period_id: @term1.id)
          sub_assignment_submissions.last.update!(grading_period_id: @term2.id)
        end

        success = service_call
        expect(success).to be true
        expect(submission.reload.grading_period_id).to be_nil
      end
    end

    describe "late_policy_status" do
      it "computes late + late = late" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          sub_assignment_submissions.update!(late_policy_status: "late")
        end

        success = service_call
        expect(success).to be true
        expect(submission.late_policy_status).to eq "late"
      end

      it "computes late + missing = late" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          sub_assignment_submissions.first.update!(late_policy_status: "late")
          sub_assignment_submissions.last.update!(late_policy_status: "missing")
        end

        success = service_call
        expect(success).to be true
        expect(submission.late_policy_status).to eq "late"
      end

      it "computes late + extended = late" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          sub_assignment_submissions.first.update!(late_policy_status: "late")
          sub_assignment_submissions.last.update!(late_policy_status: "extended")
        end

        success = service_call
        expect(success).to be true
        expect(submission.late_policy_status).to eq "late"
      end

      it "computes late + none = late" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          sub_assignment_submissions.first.update!(late_policy_status: "late")
          sub_assignment_submissions.last.update!(late_policy_status: "none")
        end

        success = service_call
        expect(success).to be true
        expect(submission.late_policy_status).to eq "late"
      end

      it "computes missing + missing = missing" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          sub_assignment_submissions.update!(late_policy_status: "missing")
        end

        success = service_call
        expect(success).to be true
        expect(submission.late_policy_status).to eq "missing"
      end

      it "computes missing + extended = missing" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          sub_assignment_submissions.first.update!(late_policy_status: "missing")
          sub_assignment_submissions.last.update!(late_policy_status: "extended")
        end

        success = service_call
        expect(success).to be true
        expect(submission.late_policy_status).to eq "missing"
      end

      it "computes missing + none = missing" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          sub_assignment_submissions.first.update!(late_policy_status: "missing")
          sub_assignment_submissions.last.update!(late_policy_status: "none")
        end

        success = service_call
        expect(success).to be true
        expect(submission.late_policy_status).to eq "missing"
      end

      it "computes extended + extended = extended" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          sub_assignment_submissions.update!(late_policy_status: "extended")
        end

        success = service_call
        expect(success).to be true
        expect(submission.late_policy_status).to eq "extended"
      end

      it "computes extended + none = extended" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          sub_assignment_submissions.first.update!(late_policy_status: "extended")
          sub_assignment_submissions.last.update!(late_policy_status: "none")
        end

        success = service_call
        expect(success).to be true
        expect(submission.late_policy_status).to eq "extended"
      end

      it "computes none + none = none" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          sub_assignment_submissions.update!(late_policy_status: "none")
        end

        success = service_call
        expect(success).to be true
        expect(submission.late_policy_status).to eq "none"
      end

      it "computes none + nil = none" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          sub_assignment_submissions.first.update!(late_policy_status: "none")
          sub_assignment_submissions.last.update!(late_policy_status: nil)
        end

        success = service_call
        expect(success).to be true
        expect(submission.late_policy_status).to eq "none"
      end

      it "computes nil + nil = nil" do
        success = service_call
        expect(success).to be true
        expect(submission.late_policy_status).to be_nil
      end
    end

    describe "submission_type" do
      it "sets the submission_type to the submission_type of checkpoints when they match" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.reply_to_topic_checkpoint.submit_homework(@student, submission_type: "discussion_topic")
          @topic.reply_to_entry_checkpoint.submit_homework(@student, submission_type: "discussion_topic")
        end

        success = service_call
        expect(success).to be true
        expect(submission.submission_type).to eq "discussion_topic"
      end

      it "sets the submission_type to nil when checkpoint submission_types don't match" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.reply_to_topic_checkpoint.submit_homework(@student, submission_type: "discussion_topic")
        end

        success = service_call
        expect(success).to be true
        expect(submission.submission_type).to be_nil
      end
    end

    describe "submitted_at" do
      it "sets the submitted_at to the most recent submitted_at, when both checkpoints are submitted" do
        now = Time.zone.now
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          Timecop.freeze(5.minutes.ago(now)) do
            @topic.reply_to_topic_checkpoint.submit_homework(@student, submission_type: "discussion_topic")
          end

          Timecop.freeze(now) do
            @topic.reply_to_entry_checkpoint.submit_homework(@student, submission_type: "discussion_topic")
          end
        end

        success = service_call
        expect(success).to be true
        expect(submission.submitted_at).to eq now
      end

      it "sets the submitted_at to nil when at least one checkpoint is not submitted" do
        Submission.suspend_callbacks(:aggregate_checkpoint_submissions) do
          @topic.reply_to_topic_checkpoint.submit_homework(@student, submission_type: "discussion_topic")
        end

        success = service_call
        expect(success).to be true
        expect(submission.submission_type).to be_nil
      end

      it "sets the submitted_at to nil when no checkpoints are submitted" do
        success = service_call
        expect(success).to be true
        expect(submission.submission_type).to be_nil
      end
    end
  end
end
