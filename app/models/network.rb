# encoding: utf-8
# == Schema Information
#
# Table name: networks
#
#  id                  :integer          not null, primary key
#  name                :string(255)
#  slug                :string(255)
#  created_at          :datetime
#  updated_at          :datetime
#  protips_count_cache :integer          default(0)
#  featured            :boolean          default(FALSE)
#

class Network < ActiveRecord::Base
  has_closure_tree order: :slug

  acts_as_taggable
  acts_as_followable

  validates :slug, uniqueness: true

  before_validation :create_slug!
  after_validation :tag_with_name!

  before_save :correct_tags
  before_save :cache_counts!
  after_create :assign_members

  scope :most_protips, order('protips_count_cache DESC')
  scope :featured, where(featured: true)

  class << self
    def slugify(name)
      if !!(name =~ /\p{Latin}/)
        name.to_s.downcase.gsub(/[^a-z0-9]+/i, '-').chomp('-')
      else
        name.to_s.tr(' ', '-')
      end
    end

    def unslugify(slug)
      slug.tr('-', ' ')
    end

    def all_with_tag(tag_name)
      Network.tagged_with(tag_name)
    end

    def networks_for_tag(tag_name)
      all_with_tag(tag_name)
    end

    def top_tags_not_networks
      top_tags.where('tags.name NOT IN (?)', Network.all.map(&:name))
    end

    def top_tags_not_in_any_networks
      top_tags.where('tags.name NOT IN (?)', Network.all.map(&:tag_list).flatten)
    end

    def top_tags
      Tagging.joins('inner join tags on tags.id = taggings.tag_id').select('distinct(name), count(name)').order('count(name) DESC').group('tags.name').where("context = 'topics'")
    end
  end

  def to_param
    self.slug
  end

  def cache_counts!
    self.protips_count_cache = self.protips.count
  end

  def create_slug!
    self.slug = self.class.slugify(self.name)
  end

  def tag_with_name!
    unless self.tag_list.include? self.name
      self.tag_list.add(self.slug)
    end
  end

  def correct_tags
    if self.tag_list_changed?
      self.tag_list = self.tag_list.uniq.select { |tag| Tag.exists?(name: tag) }.reject { |tag| (tag != self.name) && Network.exists?(name: tag) }
    end
  end

  def protips_tags_with_count
    self.protips.joins("inner join taggings on taggings.taggable_id = protips.id").joins('inner join tags on taggings.tag_id = tags.id').where("taggings.taggable_type = 'Protip' AND taggings.context = 'topics'").select('tags.name, count(tags.name)').group('tags.name').order('count(tags.name) DESC')
  end

  def ordered_tags
    self.protips_tags_with_count.having('count(tags.name) > 5').map(&:name) & self.tags
  end

  def potential_tags
    self.protips_tags_with_count.map(&:name).uniq
  end

  def protips
    @protips ||= Protip.tagged_with(self.tag_list, on: :topics)
  end

  def upvotes
    self.protips.joins("inner join likes on likes.likable_id = protips.id").where("likes.likable_type = 'Protip'").select('count(*)').count
  end

  def most_upvoted_protips(limit = nil, offset = 0)
    Protip.search_trending_by_topic_tags("sort:upvotes desc", self.tag_list, offset, limit)
  end

  def new_protips(limit = nil, offset = 0)
    Protip.search("sort:created_at desc", self.tag_list, page: offset, per_page: limit)
  end

  def featured_protips(limit = nil, offset = 0)
    #self.protips.where(:featured => true)
    Protip.search("featured:true", self.tag_list, page: offset, per_page: limit)

  end

  def flagged_protips(limit = nil, offset = 0)
    Protip.search("flagged:true", self.tag_list, page: offset, per_page: limit)
  end

  def highest_scored_protips(limit=nil, offset =0, field=:trending_score)
    Protip.search("sort:#{field} desc", self.tag_list, page: offset, per_page: limit)
  end

  def members(limit = -1, offset = 0)
    members_scope = User.where(id: Follow.for_followable(self).pluck(:follower_id)).offset(offset)
    limit > 0 ? members_scope.limit(limit) : members_scope
  end

  def new_members(limit = nil, offset = 0)
    User.where(id: Follow.for_followable(self).where('follows.created_at > ?', 1.week.ago).pluck(:follower_id)).limit(limit).offset(offset)
  end

  def assign_members
    Skill.where(name: self.tag_list).select('DISTINCT(user_id)').map(&:user).each do |member|
      member.join(self)
    end
  end

  def recent_protips_count
    self.protips.where('protips.created_at > ?', 1.week.ago).count
  end

end
