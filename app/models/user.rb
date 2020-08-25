class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable, :confirmable,
         :omniauthable, omniauth_providers: [:google_oauth2, :github, :facebook]
  
  rolify
  
  has_many :courses, dependent: :nullify
  has_many :enrollments, dependent: :nullify
  has_many :user_lessons, dependent: :nullify
  has_many :comments, dependent: :nullify
  
  include PublicActivity::Model
  tracked only:[:create, :destroy], owner: :itself

  after_create do
    UserMailer.new_user(self).deliver_later
  end

  def self.from_omniauth(access_token)
    data = access_token.info
    user = User.where(email: data['email']).first

    # Uncomment the section below if you want users to be created if they don't exist
    unless user
      user = User.create(
          email: data['email'],
          password: Devise.friendly_token[0,20],
          confirmed_at: Time.now # autoconfirm user from omniauth
      )
    else
      user.name = access_token.info.name
      user.image = access_token.info.image
      user.provider = access_token.provider
      user.uid = access_token.uid
      user.token = access_token.credentials.token
      user.expires_at = access_token.credentials.expires_at
      user.expires = access_token.credentials.expires
      user.refresh_token = access_token.credentials.refresh_token
      user.save!
    end
    user
end

  def to_s
    email
  end

  def username
    self.email.split(/@/).first
  end

  extend FriendlyId
  friendly_id :email_or_id, use: :slugged
  def email_or_id
    if self.email.present?
      self.email
    else
      self.id
    end
  end
  after_create :assign_default_role

  def assign_default_role
    if User.count == 1
      self.add_role(:admin) if self.roles.blank?
      self.add_role(:teacher)
      self.add_role(:student)
    else
      self.add_role(:student) if self.roles.blank?
      self.add_role(:teacher)
    end
  end

  validate :must_have_a_role, on: :update

  def online?
    updated_at > 2.minutes.ago
  end

  def buy_course(course)
    self.enrollments.create(course: course, price: course.price)
  end

  def view_lesson(lesson)
    user_lesson = self.user_lessons.where(lesson: lesson)
    unless user_lesson.any?
      self.user_lessons.create(lesson: lesson)
    else
      user_lesson.first.increment!(:impressions)
    end
  end

  def calculate_course_income
    update_column :course_income, (courses.map(&:income).sum)
    update_column :balance, (course_income - enrollment_expences)
  end
  
  def calculate_enrollment_expences
    update_column :enrollment_expences, (enrollments.map(&:price).sum)
    update_column :balance, (course_income - enrollment_expences)
  end

  private
  
  def must_have_a_role
    unless roles.any?
      errors.add(:roles, 'must have at least one role')
    end
  end
  
end
