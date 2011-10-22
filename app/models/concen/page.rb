require "yaml"
require "redcarpet"
require "mustache"
require "chronic"

module Concen
  class Page
    include Mongoid::Document
    include Mongoid::Timestamps

    store_in self.name.underscore.gsub("/", ".").pluralize

    references_many :children, :class_name => "Concen::Page", :foreign_key => :parent_id, :inverse_of => :parent
    referenced_in :parent, :class_name => "Concen::Page", :inverse_of => :children
    embeds_many :grid_files, :class_name => "Concen::GridFile"

    field :parent_id, :type => BSON::ObjectId
    field :level, :type => Integer
    field :title, :type => String
    field :description, :type => String
    field :slug, :type => String
    field :ancestor_slugs, :type => Array, :default => []
    field :raw_text, :type => String
    field :content, :type => Hash, :default => {}
    field :position, :type => Integer
    field :publish_time, :type => Time
    field :publish_month, :type => Time
    field :labels, :type => Array, :default => []
    field :authors, :type => Array, :default => []
    field :status, :type => String

    validates_presence_of :title
    validates_presence_of :slug
    validates_uniqueness_of :title, :scope => [:parent_id, :level], :case_sensitive => false
    validates_uniqueness_of :slug, :scope => [:parent_id, :level], :case_sensitive => false

    before_validation :parse_raw_text
    before_validation :set_title
    before_validation :set_slug
    before_validation :set_position
    before_validation :set_level
    before_save :set_publish_month
    before_save :set_ancestor_slugs
    after_save :unset_unused_dynamic_fields
    after_destroy :destroy_children
    after_destroy :destroy_grid_files
    after_destroy :reset_position

    # This scope should not be chained with other any_of criteria.
    # Because the mongo driver takes a hash for a query,
    # and a hash doesn't allow duplicate keys.
    scope :with_slug, ->(slug) { where(:slug => slug) }

    scope :with_position, where(:position.exists => true)
    scope :published, lambda {
      where(:publish_time.lte => Time.now, :status.in => [nil, /published/i])
    }
    scope :unpublished, lambda {
      any_of({:publish_time => nil}, {:publish_time.gt => Time.now})
    }

    index :parent_id, :background => true
    index :publish_time, :background => true
    index :slug, :background => true

    # Get the list of dynamic fields by checking againts this array.
    # Values should mirror the listed fields above.
    PREDEFINED_FIELDS = [:_id, :parent_id, :level, :created_at, :updated_at, :slug, :ancestor_slugs, :content, :raw_text, :position, :grid_files, :title, :description, :publish_time, :labels, :authors, :status]

    # These fields can't be overwritten by user's meta data when parsing raw_text.
    PROTECTED_FIELDS = [:_id, :parent_id, :level, :created_at, :updated_at, :content, :raw_text, :position, :grid_files, :ancestor_slugs]

    def content_in_html(key = "main", data={})
      html = nil

      if content = self.content.try(:[], key)
        # Parse mustache first.
        content = Mustache.render(content, data)

        # Parse markdown.
        markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, Concen.markdown_extensions)
        html = markdown.render content

        # Parse smartypants.
        if Concen.parse_markdown_with_smartypants
          # Temporary hack to fix smartypants bug in Redcarpet 2.0.0b5.
          html.gsub!("&#39;", "'")

          html = Redcarpet::Render::SmartyPants.render html
        end
      end

      return html
    end

    def images(filename=nil)
      search_grid_files(["png", "jpg", "jpeg", "gif"], filename)
    end

    def stylesheets(filename=nil)
      search_grid_files(["css"], filename)
    end

    def javascripts(filename=nil)
      search_grid_files(["js"], filename)
    end

    def others(filename=nil)
      excluded_ids = []
      [:images, :stylesheets, :javascripts].each do |file_type|
        excluded_ids += self.send(file_type).map(&:_id)
      end
      self.grid_files.where(:_id.nin => excluded_ids)
    end

    def search_grid_files(extensions, filename=nil)
      if filename
        self.grid_files.where(:original_filename => /.*#{filename}.*.*\.(#{extensions.join("|")}).*$/i).asc(:original_filename)
      else
        self.grid_files.where(:original_filename => /.*\.(#{extensions.join("|")}).*/i).asc(:original_filename)
      end
    end

    def underscore_hash_keys(hash)
      if hash.is_a? Hash
        new_hash = {}
        hash.each do |key, value|
          value = underscore_hash_keys(value) if value.is_a?(Hash)
          new_hash[key.gsub(" ","_").downcase.to_sym] = value
        end
        new_hash
      else
        return nil
      end
    end

    def parse_publish_time(publish_time_string)
      publish_time_string = publish_time_string.to_s
      begin
        Chronic.time_class = Time.zone
        parsed_date = Chronic.parse(publish_time_string, :now => Time.zone.now)
      rescue
        parsed_date = nil
      end
      if parsed_date
        self.publish_time = parsed_date
      elsif parsed_date = Time.zone.parse(publish_time_string)
        self.publish_time = parsed_date
      end
    end

    def published?
      self.publish_time.present?
    end

    def previous(*args)
      options = args.extract_options!
			children = self.parent.children
			children = children.published if options[:only_published]
			if options[:chronologically]
			  children = children.desc(:publish_time)
				children.where(:publish_time.lt => self.publish_time).first
			else
				children = children.desc(:position)
				children.where(:position.lt => self.position).first
			end
    end

    def next(*args)
			options = args.extract_options!
			children = self.parent.children
			children = children.published if options[:only_published]
			if options[:chronologically]
			  children = children.asc(:publish_time)
				children.where(:publish_time.gt => self.publish_time).first
			else
				children = children.asc(:position)
				children.where(:position.gt => self.position).first
			end
    end

    def first?(*args)
      options = args.extract_options!
			children = self.parent.children
			children = children.published if options[:only_published]
			if options[:chronologically]
				children = children.asc(:publish_time)
			else
				children = children.asc(:position)
			end
      if children.first
        if self.id == children.first.id
          return true
        else
          return false
        end
      else
        return false
      end
    end

    def last?(*args)
      options = args.extract_options!
			children = self.parent.children
			children = children.published if options[:only_published]
			if options[:chronologically]
				children = children.asc(:publish_time)
			else
				children = children.asc(:position)
			end
      if children.last
        if self.id == children.last.id
          return true
        else
          return false
        end
      else
        return false
      end
    end

    def authors_as_user
      users = []
      for author in self.authors
        if author.is_a?(String)
          if user = User.where(:username => author).first
            users << user
          elsif user = User.where(:email => author).first
            users << user
          elsif user = User.where(:full_name => author).first
            users << user
          end
        else
          users << user if User.where(:_id => author).first
        end
      end
      return users
    end

    protected

    def parse_raw_text
      if self.raw_text && self.raw_text.length > 0 && (self.new? || self.raw_text_changed?)
        self.content = {}
        raw_text_array = self.raw_text.split(/(?:\r?\n-{3,}\r?\n)/)
        if raw_text_array.count > 1
          meta_data = raw_text_array.delete_at(0).strip
          raw_text_array.each_with_index do |content, index|
            content = content.strip.lines.to_a
            if content.first && content.first.include?("@ ")
              # Extract content key from @ syntax.
              content_key = content.delete_at(0).gsub("@ ", "").downcase
              content_key = content_key.gsub("content", "").strip.gsub(" ", "_")
            elsif index == 0
              content_key = "main"
            else
              content_key = (index + 1).to_s
            end
            self.content[content_key] = content.join.strip
          end
        else
          meta_data = self.raw_text.strip
          self.content = {}
        end

        if meta_data = underscore_hash_keys(YAML.load(meta_data))
          # Set each value of meta data.
          meta_data.each do |key, value|
            unless PROTECTED_FIELDS.include?(key)
              if key == :publish_time
                self.parse_publish_time(value)
              else
                self.write_attribute(key, value)
              end
            end
          end

          # Set the field to nil if the value isn't present in meta data.
          # Except for authors.
          (self.attributes.keys.map{ |k| k.to_sym } - PROTECTED_FIELDS).each do |field|
            self[field] = nil if !meta_data.keys.include?(field) && field != :authors
          end
        end

        self.update_raw_text
      end
    end

    def update_raw_text
      raw_text_array = self.raw_text.split(/(?:\r?\n-{3,}\r?\n)/, 2)
      meta_data = raw_text_array.delete_at(0).lines.to_a
      meta_data.each_with_index do |line, index|
        if line.match /publish time/i
          meta_data[index] = "#{line.split(':')[0]}: #{self.publish_time}"
          if line.include? "\r\n"
            meta_data[index] << "\r\n"
          elsif line.include? "\n"
            meta_data[index] << "\n"
          end
        end
      end
      self.raw_text = meta_data.join + self.raw_text.match(/(?:\r?\n-{3,}\r?\n)/).to_s + raw_text_array.join
    end

    def unset_unused_dynamic_fields
      target_fields = {}
      for field in self.attributes.keys
        if !PREDEFINED_FIELDS.include?(field.to_sym) && self[field.to_sym].nil?
          target_fields[field.to_s] = 1
        end
      end
      Page.collection.update({"_id" => self.id}, {"$unset" => target_fields})
    end

    # Give default title ("Untitled n") when no title is given.
    def set_title
      unless self.title
        if self.parent
          if last_untitled_page = self.parent.children.where(:title => /Untitled /i).asc(:title).last
            last_untitled_number = last_untitled_page.title.split(" ").last.to_i
            self.title = "Untitled #{last_untitled_number+1}"
          else
            self.title = "Untitled 1"
          end
        else
          self.title = "Untitled 1"
        end
      end
    end

    def set_slug
      if self.slug.blank?
        self.slug = self.title.parameterize if self.title
      else
        self.slug = self.slug.parameterize
      end
    end

    def set_position
      # Only set position for newly created record.
      # It will be used by before_validation callback
      # just in case this field is used to validate something.
      unless self.persisted?
        siblings = Page.where :parent_id => self.parent_id
        if siblings.count > 0
          self.position = siblings.with_position.asc(:position).last.position + 1
        else
          self.position = 1
        end
      end
    end

    def reset_position
      affected_pages = Page.with_position.where :parent_id => self.parent_id, :position.gt => self.position
      if affected_pages.count > 0
        for page in affected_pages
          page.position = page.position - 1
          page.save
        end
      end
    end

    def set_level
      # Only set level for newly created record.
      # It will be used by before_validation callback
      # because level is part of uniqness validation of :title and :slug.
      unless self.persisted?
        if self.parent_id
          self.level = self.parent.level + 1
        else
          self.level = 0
        end
      end
    end

    def set_publish_month
      if self.publish_time
        self.publish_month = Time.zone.local(self.publish_time.year, self.publish_time.month)
      end
    end

    def set_ancestor_slugs
      parent = self.parent
      while parent
        self.ancestor_slugs << parent.slug
        parent = parent.parent
      end
      self.ancestor_slugs.reverse! if self.ancestor_slugs
    end

    def destroy_children
      for child in self.children
        child.destroy
      end
    end

    def destroy_grid_files
      for grid_file in self.grid_files
        grid_file.destroy
      end
    end
  end
end
