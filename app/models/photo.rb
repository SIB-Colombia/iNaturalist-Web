#encoding: utf-8
class Photo < ActiveRecord::Base
  acts_as_flaggable
  belongs_to :user
  has_many :observation_photos, :dependent => :destroy
  has_many :taxon_photos, :dependent => :destroy
  has_many :guide_photos, :dependent => :destroy, :inverse_of => :photo
  has_many :observations, :through => :observation_photos
  has_many :taxa, :through => :taxon_photos
  
  attr_accessor :api_response
  serialize :metadata
  
  # licensing extras
  attr_accessor :make_license_default
  attr_accessor :make_licenses_same
  MASS_ASSIGNABLE_ATTRIBUTES = [:make_license_default, :make_licenses_same]
  
  before_save :set_license, :trim_fields
  after_save :update_default_license,
             :update_all_licenses,
             :index_observations
  after_destroy :create_deleted_photo
  
  COPYRIGHT = 0
  NO_COPYRIGHT = 7
  
  LICENSE_INFO = {
    0 => {:code => "C",                       :short => "(c)",          :name => "Copyright", :url => "http://en.wikipedia.org/wiki/Copyright"},
    1 => {:code => Observation::CC_BY_NC_SA,  :short => "CC BY-NC-SA",  :name => "Attribution-NonCommercial-ShareAlike License", :url => "http://creativecommons.org/licenses/by-nc-sa/3.0/"},
    2 => {:code => Observation::CC_BY_NC,     :short => "CC BY-NC",     :name => "Attribution-NonCommercial License", :url => "http://creativecommons.org/licenses/by-nc/3.0/"},
    3 => {:code => Observation::CC_BY_NC_ND,  :short => "CC BY-NC-ND",  :name => "Attribution-NonCommercial-NoDerivs License", :url => "http://creativecommons.org/licenses/by-nc-nd/3.0/"},
    4 => {:code => Observation::CC_BY,        :short => "CC BY",        :name => "Attribution License", :url => "http://creativecommons.org/licenses/by/3.0/"},
    5 => {:code => Observation::CC_BY_SA,     :short => "CC BY-SA",     :name => "Attribution-ShareAlike License", :url => "http://creativecommons.org/licenses/by-sa/3.0/"},
    6 => {:code => Observation::CC_BY_ND,     :short => "CC BY-ND",     :name => "Attribution-NoDerivs License", :url => "http://creativecommons.org/licenses/by-nd/3.0/"},
    7 => {:code => "PD",                      :short => "PD",           :name => "Public domain", :url => "http://en.wikipedia.org/wiki/Public_domain"},
    8 => {:code => "GFDL",                    :short => "GFDL",         :name => "GNU Free Documentation License", :url => "http://www.gnu.org/copyleft/fdl.html"}
  }
  LICENSE_NUMBERS = LICENSE_INFO.keys
  LICENSE_INFO.each do |number, info|
    const_set info[:code].upcase.gsub(/\-/, '_'), number
    const_set info[:code].upcase.gsub(/\-/, '_') + "_CODE", info[:code]
  end

  SQUARE = 75
  THUMB = 100
  SMALL = 240
  MEDIUM = 500
  LARGE = 1024
  
  def to_s
    "<#{self.class} id: #{id}, user_id: #{user_id}>"
  end

  def to_plain_s
    "#{type.underscore.humanize} #{id} by #{attribution}"
  end
  
  def licensed_if_no_user
    if user.blank? && (license == COPYRIGHT || license.blank?)
      errors.add(
        :license, 
        "must be set if the photo wasn't added by an #{CONFIG.site_name_short} user.")
    end
  end
  
  def set_license
    return true unless license.blank?
    return true unless user
    self.license = Photo.license_number_for_code(user.preferred_photo_license)
    true
  end

  def trim_fields
    %w(native_realname native_username).each do |c|
      self.send("#{c}=", read_attribute(c).to_s[0..254]) if read_attribute(c)
    end
    true
  end
  
  # Return a string with attribution info about this photo
  def attribution
    if license == PD
      I18n.t('copyright.no_known_copyright_restrictions', :name => attribution_name, :license_name => I18n.t("copyright.#{license_name.gsub(' ','_').gsub('-','_').downcase}", :default => license_name))
    elsif open_licensed?
      I18n.t('copyright.some_rights_reserved_by', :name => attribution_name, :license_short => license_short)
    else
      I18n.t('copyright.all_rights_reserved', :name => attribution_name)
    end
  end

  def attribution_name
    if !native_realname.blank?
      native_realname
    elsif !native_username.blank?
      native_username
    elsif user
      user.name.blank? ? user.login : user.name
    else
      I18n.t('copyright.anonymous')
    end
  end
  
  def license_short
    LICENSE_INFO[license.to_i].try(:[], :short)
  end
  
  def license_name
    LICENSE_INFO[license.to_i].try(:[], :name)
  end
  
  def license_code
    LICENSE_INFO[license.to_i].try(:[], :code)
  end
  
  def license_url
    LICENSE_INFO[license.to_i].try(:[], :url)
  end
  
  def copyrighted?
    license.to_i == COPYRIGHT
  end
  
  def creative_commons?
    license.to_i > COPYRIGHT && license.to_i < NO_COPYRIGHT
  end

  def open_licensed?
    license.to_i > COPYRIGHT && license != PD
  end
  
  # Try to choose a single taxon for this photo.  Only works if class has 
  # implemented to_taxa
  def to_taxon
    return unless respond_to?(:to_taxa)
    photo_taxa = to_taxa(:lexicon => TaxonName::SCIENTIFIC_NAMES, :valid => true, :active => true)
    photo_taxa = to_taxa(:lexicon => TaxonName::SCIENTIFIC_NAMES) if photo_taxa.blank?
    photo_taxa = to_taxa if photo_taxa.blank?
    return if photo_taxa.blank?
    photo_taxa = photo_taxa.sort_by{|t| t.rank_level || Taxon::ROOT_LEVEL + 1}
    candidate = photo_taxa.detect(&:species_or_lower?) || photo_taxa.first
    # if there are synonyms, don't decide
    if photo_taxa.detect{|t| t.name == candidate.name && t.id != candidate.id}
      nil
    else
      candidate
    end
  end
  
  # Sync photo object with its native source.  Implemented by descendents
  def sync
    nil
  end
  
  def update_attributes(attributes)
    MASS_ASSIGNABLE_ATTRIBUTES.each do |a|
      self.send("#{a}=", attributes.delete(a.to_s)) if attributes.has_key?(a.to_s)
      self.send("#{a}=", attributes.delete(a)) if attributes.has_key?(a)
    end
    super(attributes)
  end
  
  def update_default_license
    return true unless [true, "1", "true"].include?(@make_license_default)
    user.update_attribute(:preferred_photo_license, Photo.license_code_for_number(license))
    true
  end
  
  def update_all_licenses
    return true unless [true, "1", "true"].include?(@make_licenses_same)
    Photo.where(user_id: user_id).update_all(license: license)
    true
  end

  def index_observations
    Observation.elastic_index!(scope: observations, delay: true)
  end

  def editable_by?(user)
    return false if user.blank?
    user.id == user_id || observations.exists?(:user_id => user.id)
  end

  def orphaned?
    return false if observation_photos.loaded? ? observation_photos.size > 0 : observation_photos.exists?
    return false if taxon_photos.loaded? ? taxon_photos.size > 0 : taxon_photos.exists?
    return false if guide_photos.loaded? ? guide_photos.size > 0 : guide_photos.exists?
    true
  end

  def source_title
    self.class.name.gsub(/Photo$/, '').underscore.humanize.titleize
  end

  def best_url(size = "medium")
    size = size.to_s
    sizes = %w(original large medium small thumb square)
    size = "medium" unless sizes.include?(size)
    size_index = sizes.index(size)
    methods = sizes[size_index.to_i..-1].map{|s| "#{s}_url"} + ['original']
    try_methods(*methods)
  end

  def as_json(options = {})
    options[:except] ||= []
    options[:except] += [:metadata, :file_content_type, :file_file_name,
      :file_file_size, :file_processing, :file_updated_at, :mobile,
      :original_url]
    options[:methods] ||= []
    options[:methods] += [:license_name, :license_url, :attribution]
    super(options)
  end

  def flagged_with(flag, options = {})
    if flag.flag == Flag::COPYRIGHT_INFRINGEMENT
      if options[:action] == "created"
        styles = %w(original large medium small thumb square)
        updates = [styles.map{|s| "#{s}_url = ?"}.join(', ')]
        updates += styles.map do |s|
          FakeView.image_url("copyright-infringement-#{s}.png").to_s
        end
        Photo.where(id: id).update_all(updates)
      elsif %w(resolved destroyed).include?(options[:action])
        Photo.repair_single_photo(self)
      end
      observations.each(&:update_stats)
    end
  end

  def self.repair_photos_for_user(user, type)
    count = 0
    user.photos.where(type: type).find_each do |photo|
      next if Photo.valid_remote_photo_url?(photo.original_url)
      next if Photo.valid_remote_photo_url?(photo.large_url)
      p, errors = photo.repair(no_save: true)
      unless errors.blank?
        Rails.logger.error "[ERROR] Failed to repair #{p}: #{errors.inspect}"
        next
      end
      Photo.turn_remote_photo_into_local_photo(p)
      unless p.valid?
        Rails.logger.error "[ERROR] Failed to save #{p}: #{p.errors.full_messages.to_sentence}"
        next
      end
      count += 1
    end
    Rails.logger.info "[INFO] Repaired #{count} #{type}s for #{user}"
  end

  def self.repair_single_photo(photo)
    if photo.subtype && klass = (photo.subtype.constantize rescue nil)
      if klass < Photo
        # we have a photo with a valid Photo subtype (cached remote photo)
        repair_photo = klass.new(photo.attributes.merge(type: photo.subtype))
        # repair as if it were the remote photo, but don't save anything
        repaired, errors = repair_photo.repair(no_save: true)
        unless errors.blank?
          return [ photo, errors ]
        end
        # if that succeded, update this photo with the repaired remote URL
        photo.file = URI(repaired.original_url || repaired.large_url ||
          repaired.medium_url || repaired.small_url)
        photo.save
        return [ photo, { } ]
      end
    end
    if photo.respond_to?(:repair)
      return photo.repair
    end
  end

  # used in the ObservationsController to create an un-saved
  # LocalPhoto from an unsaved remote photo and inherit
  # necessary attributes
  def self.local_photo_from_remote_photo(remote_photo)
    # inherit native_* and other attributes from remote photos
    remote_photo_attrs = remote_photo.attributes.select do |k,v|
      k =~ /^native/ ||
        [ "user_id", "license", "mobile", "metadata" ].include?(k)
    end
    photo_url = remote_photo.try_methods(:original_url, :large_url, :medium_url, :small_url)
    remote_photo_attrs["native_original_image_url"] = photo_url
    remote_photo_attrs["subtype"] = remote_photo.class.name
    # stub this LocalPhoto's file with the remote photo URL
    remote_photo_attrs["file"] = URI(photo_url)
    LocalPhoto.new(remote_photo_attrs)
  end

  # to be used primarly for retroactive caching of remote photos
  def self.turn_remote_photo_into_local_photo(remote_photo)
    return unless remote_photo && remote_photo.class < Photo
    return unless fetch_url = remote_photo.best_available_url
    remote_photo.type = "LocalPhoto"
    remote_photo.subtype = remote_photo.class.name
    remote_photo.native_original_image_url = fetch_url
    remote_photo = remote_photo.becomes(LocalPhoto)
    remote_photo.file = fetch_url
    remote_photo.save
  end

  # to be used primarly for turn_remote_photo_into_local_photo
  def best_available_url
    [ :original, :large, :medium, :small ].each do |s|
      url = self.send("#{ s }_url")
      if url && Photo.valid_remote_photo_url?(url)
        return url
      end
    end
    nil
  end

  def self.valid_remote_photo_url?(remote_photo_url)
    if head = fetch_head(remote_photo_url)
      # image must return 200 and have a valid image mime-type
      return head.code == "200" &&
        head.to_hash["content-type"].any?{ |t| t =~ /(jpe?g|png|gif|octet-stream)/i }
    end
    false
  end

  # Retrieve info about a photo from its native source given its native id.  
  # Should be implemented by descendents
  def self.get_api_response(native_photo_id, options = {})
    nil
  end
  
  # Create a new Photo object from an API response.  Should be implemented by 
  # descendents
  def self.new_from_api_response(api_response, options = {})
    nil
  end
  
  # Destroy a photo if it no longer belongs to any observations or taxa
  def self.destroy_orphans(ids)
    photos = Photo.where(id: [ ids ].flatten)
    return if photos.blank?
    photos.each do |photo|
      photo.destroy if photo.orphaned?
    end
  end
  
  def self.license_number_for_code(code)
    return COPYRIGHT if code.blank?
    LICENSE_INFO.detect{|k,v| v[:code] == code}.try(:first)
  end
  
  def self.license_code_for_number(number)
    LICENSE_INFO[number].try(:[], :code)
  end
  
  def self.default_json_options
    {
      :methods => [:license_code, :attribution],
      :except => [:original_url, :file_processing, :file_file_size, 
        :file_content_type, :file_file_name, :mobile, :metadata, :user_id, 
        :native_realname, :native_photo_id]
    }
  end

  def as_indexed_json(options={})
    json = {
      id: id,
      license_code: (license_code.blank? || license.blank? || license == 0) ?
        nil : license_code.downcase,
      attribution: attribution,
      url: (self.is_a?(LocalPhoto) && processing?) ? nil : square_url
    }
    options[:sizes] ||= [ ]
    options[:sizes].each do |size|
      json["#{ size }_url"] = best_url(size)
    end
    json
  end

  private

  def self.attributes_protected_by_default
    super - [inheritance_column]
  end

  def create_deleted_photo
    DeletedPhoto.create(
      :photo_id => id,
      :user_id => user_id
    )
    true
  end

end
