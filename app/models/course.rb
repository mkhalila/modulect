class Course < ApplicationRecord

  validates :name, presence: true
  validates :code, presence: true, :uniqueness => true
  validates :level, presence: true

end
