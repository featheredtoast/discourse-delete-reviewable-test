# frozen_string_literal: true

# name: discourse-delete-test
# about: test deleting post
# version: 0.1.0
# authors: Jeff Wong
# url: https://github.com/featheredtoast/discourse-delete-test

def trigger_post_classification(post)
  # Use Job queue
  # Rails.logger.debug("sift_debug: Using Job method")
  Jobs.enqueue(:delete_post, post_id: post.id)
  # performed_by = Discourse.system_user
  # PostDestroyer.new(performed_by, post).destroy
end

after_initialize do
  on(:post_created) do |post, _params|
    begin
      trigger_post_classification(post)
    rescue StandardError => e
      Rails.logger.error("sift_debug: Exception in post_create: #{e.inspect}")
      raise e
    end
  end

  require_dependency 'jobs/base'
  module ::Jobs
    class DeletePost < ::Jobs::Base
      def execute(args)
        post = Post.find(args[:post_id])
        reporter = Discourse.system_user
        # PostDestroyer.new(performed_by, post).destroy
        ReviewableTestPost.needs_review!(
          created_by: reporter, target: post, topic: post.topic,
          reviewable_by_moderator: true,
          payload: { post_cooked: post.cooked }
        ).tap do |reviewable|

          reviewable.add_score(
            reporter, PostActionType.types[:inappropriate],
            created_at: reviewable.created_at
          )
        end
      end
    end
  end

  require_dependency 'reviewable'
  class ::ReviewableTestPost < ::Reviewable
    def post
      @post ||= (target || Post.with_deleted.find_by(id: target_id))
    end

    def build_actions(actions, _guardian, _args)
      return [] unless pending?

      build_action(actions, :confirm_failed, icon: 'check', key: 'confirm_fails_policy')
      build_action(actions, :ignore, icon: 'times', key: 'dismiss')
    end

    def perform_confirm_failed(performed_by, _args)
      # If post has not been deleted (i.e. if setting is on)
      # Then delete it now
      PostDestroyer.new(performed_by, post).destroy if post.deleted_at.blank?
      successful_transition :approved, :agreed
    end

    private

    def build_action(actions, id, icon:, bundle: nil, key:)
      actions.add(id, bundle: bundle) do |action|
        action.icon = icon
        action.label = "js.sift.#{key}"
      end
    end

    def successful_transition(to_state, update_flag_status, recalculate_score: true)
      create_result(:success, to_state) do |result|
        result.recalculate_score = recalculate_score
        result.update_flag_stats = { status: update_flag_status, user_ids: [created_by_id] }
      end
    end
  end
end
