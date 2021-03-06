# require 'spec_helper'

# describe Plan do

#   before { @plan = Plan.new(name: "My Test Plan", visibility: :private) }

#   subject { @plan }

#   it { should respond_to(:name) }
#   it { should respond_to(:requirements_template_id) }
#   it { should respond_to(:solicitation_identifier) }
#   it { should respond_to(:submission_deadline) }
#   it { should respond_to(:visibility) }

#   it { should have_many(:users).through(:user_plans) }
#   it { should have_many(:plan_states) }
#   it { should have_many(:published_plans) }

#   it { should be_valid }

#   describe "when name is blank" do
#     before { @plan.name = "" }
#     it { should_not be_valid }
#   end

#   describe "when visibility is blank" do
#     before { @plan.visibility = "" }
#     it { should_not be_valid }
#   end

#   describe "when trying to set a valid visibility" do
#     it "should be valid" do
#       valid_visibilities = %w[institutional public private]
#       valid_visibilities.each do |valid_visibility|
#         @plan.visibility = valid_visibility
#         @plan.should be_valid
#       end
#     end
#   end

#   describe "when trying to set a nonvalid visibility" do
#     it "should not be valid" do
#       non_valid_visibilities = %w[this is not a valid visibility]
#       non_valid_visibilities.each do |non_valid_visibility|
#         @plan.visibility = non_valid_visibility
#         @plan.should_not be_valid
#       end
#     end
#   end

#   describe "should belong to one or many users" do
#     let(:user) { FactoryGirl.create(:user) }

#     before { @plan.users << user }

#     it "should be able to access it's users" do
#       @plan.users.count.eql?(1)
#       @plan.users.first.eql?(user)
#     end
#   end
# end
