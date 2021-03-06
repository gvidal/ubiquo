require 'digest/sha1'
class UbiquoUser < ActiveRecord::Base

  # Creates the photo attachment to the user and a resized thumbnail
  file_attachment(:photo, {
    :visibility => "protected",
    :styles     => { :thumb => "66x66>" },
    :storage    => ubiquo_config_call(:photo_storage,
                                      :context => :ubiquo_authentication)
  })

  # Virtual attribute for the unencrypted password
  attr_accessor :password

  validates :name, :surname, :presence => true
  validates :password_confirmation, :presence => { :if => :password_required? }
  validates :password, :presence     => true,
                       :length       => { :within => 4..40 },
                       :confirmation => true,
                       :if           => :password_required?
  validates :login, :presence   => true,
                    :length     => { :within => 3..40 },
                    :uniqueness => { :case_sensitive => false }
  validates :email, :presence   => true,
                    :uniqueness => { :case_sensitive => false },
                    :format     => { :with => /\A([a-z0-9#_.-]+)@([a-z0-9-]+)\.([a-z.]+)\Z/i }

  before_save :encrypt_password

  # prevents a ubiquo_user from submitting a crafted form that bypasses activation
  # anything else you want your ubiquo_user to change should be added here.
  attr_accessible :login, :email, :password, :password_confirmation, :is_admin, :is_active, :role_ids, :photo, :name, :surname, :locale

  scope :admin, lambda { |value| where(:is_admin => value.to_bool) }
  scope :active, lambda { |value| where(:is_active => value.to_bool) }

  filtered_search_scopes :text => [:name, :surname, :login],
                         :enable => [:admin, :active]

  # Creates first user. Used when installing ubiquo. It shouldn't work in production mode.
  def self.create_first(login,password)
    unless Rails.env.production? || self.count > 0
      admin_user = {
        :login => login,
        :password => password,
        :password_confirmation => password,
        :email => 'foo@bar.com',
        :name => 'Super',
        :surname => 'Admin',
        :is_active => true,
        :is_admin => true,
        :locale => I18n.locale.to_s
      }
      user = UbiquoUser.create(admin_user)
      unless user.new_record?
        user.is_superadmin = true
        user.save
      end
      user
    end
  end

  # Authenticates a ubiquo_user by their login name and unencrypted password.  Returns the ubiquo_user or nil.
  def self.authenticate(login, password)
    u = find_by_login(login) # need to get the salt
    (u && (u.authenticated?(password) ? u : nil) && (u.is_active? ? u : nil))
  end

  # Encrypts some data with the salt.
  def self.encrypt(password, salt)
    Digest::SHA1.hexdigest("--#{salt}--#{password}--")
  end

  # Encrypts the password with the ubiquo_user salt
  def encrypt(password)
    self.class.encrypt(password, salt)
  end

  def authenticated?(password)
    crypted_password == encrypt(password)
  end

  def remember_token?
    remember_token_expires_at && Time.now.utc < remember_token_expires_at
  end

  # These create and unset the fields required for remembering ubiquo_users between browser closes
  def remember_me
    remember_me_for Ubiquo::Settings.context(:ubiquo_authentication).get(:remember_time)
  end

  def remember_me_for(time)
    remember_me_until time.from_now.utc
  end

  # The current ubiquo_user will not expire until 'time' is reached
  def remember_me_until(time)
    self.remember_token_expires_at = time
    self.remember_token            = encrypt("--#{remember_token_expires_at}--")
    self.save
  end

  # Expire current_ubiquo_user inmediately
  def forget_me
    self.remember_token_expires_at = nil
    self.remember_token            = nil
    self.save
  end

  def reset_password!
    (password = SecureRandom.base64(6)).tap do
      self.password = password
      self.password_confirmation = password
      self.save
    end
  end

  def full_name
    "#{self.surname}, #{self.name}"
  end

  protected

  # before filter
  def encrypt_password
    return if password.blank?
    self.salt = Digest::SHA1.hexdigest("--#{Time.now.to_s}--#{login}--") if new_record?
    self.crypted_password = encrypt(password)
  end

  def password_required?
    crypted_password.blank? || !password.blank?
  end

end
