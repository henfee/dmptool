class User < ActiveRecord::Base
  acts_as_paranoid

  serialize :prefs, Hash

  belongs_to :institution
  has_many :user_plans
  has_many :plans, through: :user_plans
  has_many :comments
  has_many :authentications
  has_many :authorizations
  has_many :roles, through: :authorizations

  attr_accessor :ldap_create, :password, :password_confirmation

  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
  validates :institution_id, presence: true, numericality: true
  validates :email, presence: true, uniqueness: { :case_sensitive => false }, format: { with: VALID_EMAIL_REGEX }
  validates :prefs, presence: true
  validates :login_id, presence: true, uniqueness: { case_sensitive: false }

  before_validation :create_default_preferences, if: Proc.new { |x| x.prefs.empty? }
  before_validation :add_default_institution, if: Proc.new { |x| x.institution_id.nil? }
  before_create :create_cookie_salt, if: Proc.new { |x| x.cookie_salt.nil? }

  def self.authenticate_with_salt(id, cookie_salt)
    user = find_by_id(id)
    (user && user.cookie_salt == cookie_salt) ? user : nil
  end

  def ldap_user?
    self.authentications.where(:provider => 'ldap').first.present?
  end

  def ensure_ldap_authentication(uid)
    unless Authentication.find_by_user_id_and_provider(self.id, 'ldap')
      Authentication.create(:user => self, :provider => 'ldap', :uid => uid)
    end
  end

  def full_name
    [first_name, last_name].join(" ")
  end

  private

  def create_cookie_salt
    self.cookie_salt = secure_hash("#{self.created_at}--UCOP--DMP")
  end

  def add_default_institution
    self.institution_id = 0
  end

  def create_default_preferences
    default_prefs = {
        users:                   {
            role_granted: true
        },
        dmp_owners_and_co:       {
            new_comment: true,
            commited:    true,
            published:   true,
            submitted:   true
        },
        dmp_co:                  {
            submitted:    true,
            deactivated:  true,
            deleted:      true,
            new_co_owner: true
        },
        requirement_editors:     {
            commited:  true,
            deactived: true,
            deleted:   true
        },
        resource_editors:        {
            commited:            true,
            deactived:           true,
            deleted:             true,
            associated_commited: true
        },
        institutional_reviewers: {
            submitted:         true,
            new_comment:       true,
            approved_rejected: true
        }
    }

    self.prefs = default_prefs
  end

  def secure_hash(string)
    Digest::SHA2.hexdigest(string)
  end
end
