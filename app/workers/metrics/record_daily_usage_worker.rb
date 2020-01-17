module Metrics
  class RecordDailyUsageWorker
    include Sidekiq::Worker
    sidekiq_options queue: :low_priority, retry: 10

    def perform
      # Articles published in the past 24 hours with at least 15 "score" (positive/negative reactions)
      articles_min_15_score_past_24h = Article.published.where("score >= ? AND published_at > ?", 15, 1.day.ago).size
      DataDogStatsClient.count("articles.min_15_score_past_24h", articles_min_15_score_past_24h, tags: { resource: "articles" })

      # Articles published in the past 24 hours with at least 15 "score" (positive/negative reactions)
      articles_min_15_comment_score_past_24h = Article.published.where("comment_score >= ? AND published_at > ?", 15, 1.day.ago).size
      DataDogStatsClient.count("articles.min_15_comment_score_past_24h", articles_min_15_comment_score_past_24h, tags: { resource: "articles" })

      # Articles published in the past 24 which were that user's first article
      first_articles_past_24h = Article.where(nth_published_by_author: 1).where("published_at > ?", 1.day.ago).size
      DataDogStatsClient.count("articles.first_past_24h", first_articles_past_24h, tags: { resource: "articles" })

      # Users who signed up in the past 24 hours who have made at least 1 comment so far
      new_users_min_1_comment_past_24h = User.where("comments_count >= ? AND created_at > ?", 1, 24.hours.ago).size
      DataDogStatsClient.count("users.new_min_1_comment_past_24h", new_users_min_1_comment_past_24h, tags: { resource: "users" })

      # Total negative reactions in the past 24 hours
      nagative_reactions_past_24h = Reaction.where("points < 0").where("created_at > ?", 1.day.ago).size
      DataDogStatsClient.count("reactions.negative_past_24h", nagative_reactions_past_24h, tags: { resource: "reactions" })

      # Total abuse (etc.) reports in the past 24 hours
      reports_past_24_hours = FeedbackMessage.where(category: ["spam", "other", "rude or vulgar", "harassment"]).where("created_at > ?", 1.day.ago).size
      DataDogStatsClient.count("feedback_messages.reports_past_24_hours", reports_past_24_hours, tags: { resource: "feedback_messages" })

      # Counts of total days active (1-7) in the past week, e.g. 5000 users visited once this week, 3500 visited twice, etc.
      get_days_active_past_week_counts
    end

    private

    def get_days_active_past_week_counts
      ids_by_day = []
      7.times do |i|
        ids_by_day << PageView.where("created_at > ? AND created_at < ?", (i + 1).days.ago, i.days.ago).where.not(user_id: nil).pluck(:user_id).uniq
      end
      flat_id_list = ids_by_day.flatten.uniq
      non_new_user_ids = User.where("created_at < ?", 7.days.ago).where(id: flat_id_list).pluck(:id)
      new_user_ids = User.where("created_at > ? AND created_at < ?", 8.days.ago, 7.days.ago).where(id: flat_id_list).pluck(:id)
      record_active_days_of_group(ids_by_day, non_new_user_ids, "established")
      record_active_days_of_group(ids_by_day, new_user_ids, "new")
    end

    def record_active_days_of_group(ids_by_day, user_ids, group)
      user_ids_by_day = ids_by_day.map { |a| a & user_ids }
      distinct_user_values = user_ids_by_day.flatten.group_by(&:itself).transform_values(&:count).values
      distinct_counts = distinct_user_values.group_by(&:itself).transform_values(&:count)
      distinct_counts.keys.each do |key|
        DataDogStatsClient.count("users.#{group}_active_#{key}_days_past_7_days", distinct_counts[key], tags: { resource: "users" })
      end
    end
  end
end
