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

  on(:post_edited) do |post, _params|
    begin
      trigger_post_classification(post)
    rescue StandardError => e
      Rails.logger.error("sift_debug: Exception in post_edited: #{e.inspect}")
      raise e
    end
  end

  require_dependency 'jobs/base'
  module ::Jobs
    class DeletePost < ::Jobs::Base
      def execute(args)
        post = Post.find(args[:post_id])
        performed_by = Discourse.system_user
        PostDestroyer.new(performed_by, post).destroy
      end
    end
  end
end
