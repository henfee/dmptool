class PlansController < ApplicationController

  before_action :require_login, except: [:public, :show]
  #note show will need to be protected from logins in some cases, but only from non-public plan viewing
  before_action :set_plan, only: [:show, :edit, :update, :destroy, :publish, :export, :details, :preview, :perform_review, :coowners, :add_coowner_autocomplete]
  #before_action :select_requirements_template, only: [:select_dmp_template]

  # GET /plans
  # GET /plans.json
  def index
   user = User.find(current_user.id)
   @owned_plans = user.owned_plans
   @coowned_plans = user.coowned_plans
   plan_ids = UserPlan.where(user_id: user.id).pluck(:plan_id) unless user.id.nil?
   @plans = Plan.where(id: plan_ids)
   count
    case params[:scope]
      when "all"
        @plans = @plans.page(params[:page]).per(9999)
      when "all_limited"
        @plans = @plans.page(params[:page]).per(5)
      when "owned"
        @plans = @owned_plans.page(params[:page]).per(5)
      when "coowned"
        @plans = @coowned_plans.page(params[:page]).per(5)
      when "approved"
        @plans = @plans.approved.page(params[:page]).per(5)
      when "submitted"
        @plans = @plans.submitted.page(params[:page]).per(5)
      when "committed"
        @plans = @plans.committed.page(params[:page]).per(5)
      when "rejected"
        @plans = @plans.rejected.page(params[:page]).per(5)
      else
        @plans = @plans.order(created_at: :asc).page(params[:page]).per(5)
    end
    @planstates = PlanState.page(params[:page]).per(5)
  end

  # GET /plans/1
  # GET /plans/1.json
  def show
    render(layout: "clean")
  end

  # GET /plans/new
  def new
    @plan = Plan.new
    @comment = Comment.new
  end

  # POST /plans
  # POST /plans.json
  def create
    flash[:notice] = []
    @plan = Plan.new(plan_params)
    respond_to do |format|
      if @plan.save
        UserPlan.create!(user_id: current_user.id, plan_id: @plan.id, owner: true)
        PlanState.create!(plan_id: @plan.id, state: :new, user_id: current_user.id )
        add_coowner_autocomplete
        flash[:alert]
        format.html { flash[:notice] << "Plan was successfully updated."
                  redirect_to edit_plan_path(@plan)}
        format.json { render action: 'show', status: :created, location: @plan }
      else
        add_coowner_autocomplete
        format.html { render action: 'new' }
        format.json { render json: @plan.errors, status: :unprocessable_entity }
      end
    end
  end

  # GET /plans/1/edit
  def edit
    @customization = ResourceContext.where(requirements_template_id: @plan.requirements_template_id, institution_id: current_user.institution_id)
    set_comments
    coowners
  end

  # PATCH/PUT /plans/1
  # PATCH/PUT /plans/1.json
  def update
    flash[:notice] = []
    flash[:alert] = []
    @customization = ResourceContext.where(requirements_template_id: @plan.requirements_template_id, institution_id: current_user.institution_id)
    set_comments
    coowners
    add_coowner_autocomplete
    respond_to do |format|
      if flash[:alert].include?("The user you entered with email #{@email} was not found")
        format.html { flash[:alert]
              redirect_to edit_plan_path(@plan)}
      elsif flash[:alert].include?("The user you chose is already a #{@item_description}")
        format.html { flash[:alert]
              redirect_to edit_plan_path(@plan)}
      elsif flash[:alert].include?(flash[:alert] = "The user chosen is the Owner of the Plan. An owner cannot be #{@item_description} for the same plan")
        format.html { flash[:alert]
              redirect_to edit_plan_path(@plan)}
      else
        if @plan.update(plan_params)
          format.html { flash[:notice] << "Plan was successfully updated."
                  redirect_to edit_plan_path(@plan)}
          format.json { head :no_content }
        else
          add_coowner_autocomplete
          format.html { render action: 'edit' }
          format.json { render json: @plan.errors, status: :unprocessable_entity }
        end
      end
    end
  end
  # DELETE /plans/1
  # DELETE /plans/1.json
  def destroy
    @plan.destroy
    respond_to do |format|
      format.html { redirect_to plans_url }
      format.json { head :no_content }
    end
  end

  def template_information
      public_plans = Plan.public_visibility
      current_user_plan_ids = UserPlan.where(user_id: current_user.id).pluck(:plan_id)
      user_plans = Plan.where(id: current_user_plan_ids)
      @plans = user_plans + public_plans
      @plans = Kaminari.paginate_array(@plans).page(params[:page]).per(5)
  end

  def copy_existing_template
    @comment = Comment.new
    comments = Comment.all
    id = params[:plan].to_i unless params[:plan].blank?
    plan = Plan.where(id: id).first
    @plan = plan.dup include: [:responses]
    render action: "copy_existing_template"
  end

  def perform_review
    @comment = Comment.new
    comments = Comment.where(plan_id: @plan.id)
    @reviewer_comments = comments.reviewer_comments.page(params[:page]).per(5)
  end

  def review_dmps
    if user_role_in?(:institutional_reviewer, :institutional_admin)
      institutions = Institution.find(current_user.institution_id).subtree_ids
      @submitted_plans = Plan.plans_to_be_reviewed(institutions)
      @approved_plans = Plan.plans_approved(institutions)
      @rejected_plans = Plan.plans_rejected(institutions)
      @plans = @submitted_plans + @approved_plans + @rejected_plans
    else
      user_role_in?(:dmp_admin)
      @submitted_plans = Plan.plans_to_be_reviewed(Institution.all.ids)
      @approved_plans = Plan.plans_approved(Institution.all.ids)
      @rejected_plans = Plan.plans_rejected(Institution.all.ids)
      @plans = @submitted_plans + @approved_plans + @rejected_plans
    end
    case params[:scope]
      when "submitted"
        @plans = @submitted_plans.page(params[:page]).per(5)
      when "approved"
        @plans = @approved_plans.page(params[:page]).per(5)
      when "rejected"
        @plans = @rejected_plans.page(params[:page]).per(5)
      when "all_limited"
        @plans = Kaminari.paginate_array(@plans).page(params[:page]).per(5)
      else
        @plans = Kaminari.paginate_array(@plans).page(params[:page])
    end
    review_count
  end

  def select_dmp_template
    req_temp = RequirementsTemplate.
                  includes(:institution).
                  where(active: true).
                  any_of(visibility: :public, institution_id: [current_user.institution.subtree_ids])

    if !params[:q].blank?
      req_temp = req_temp.name_search_terms(params[:q])
    end
    if !params[:s].blank? && !params[:e].blank?
      req_temp = req_temp.letter_range(params[:s], params[:e])
    end

    process_requirements_template(req_temp)

    @back_to = plan_template_information_path
    @back_text = "<< Create New DMP"
    @submit_to = new_plan_path
    @submit_text = "DMP Overview Page >>"

  end

  def details
    template_id = @plan.requirements_template_id
    @requirements_template = RequirementsTemplate.find(template_id)
    unless @requirements_template.nil?
      @requirements = @requirements_template.requirements
      if params[:requirement_id].blank?
        requirement = @requirements_template.first_question
        if requirement.nil?
          redirect_to(resource_contexts_path, :notice =>
              "The DMP template you are attempting to customize has no requirements. A template must contain at least one requirement. \"#{@requirements_template.name}\" needs to be fixed before you may continue customizing it.") and return
        end
        params[:requirement_id] = requirement.id.to_s
      end
      @requirement = Requirement.find(params[:requirement_id]) unless params[:requirement_id].blank?
      @resource_contexts = ResourceContext.where(requirement_id: @requirement.id, institution_id: current_user.institution_id, requirements_template_id: @requirements_template.id)
      @guidance_resources = display_text(@resource_contexts)
      @url_resources = display_value(@resource_contexts)
      @suggested_resources = display_suggested(@resource_contexts)
      @example_resources = display_example(@resource_contexts)
      @response = Response.where(plan_id: @plan.id, requirement_id: @requirement.id).first
      if @response.nil?
        @response = Response.new
      end

      @next_requirement = @requirements[@requirements.index(@requirement) + 1]
      if @next_requirement.nil?
        ## would go back to the 1st Requirement in the list
        @next_requirement_id = @requirements_template.first_question.id
      else
        ## traverse through the next requirement in the list
        @next_requirement_id = @next_requirement.id
      end
    end
  end

  def change_visibility
    id = params[:plan_id].to_i unless params[:plan_id].blank?
    plan = Plan.find(id)
    plan.visibility = params[:visibility]
    respond_to do |format|
      if plan.save
        format.html { redirect_to :back }
        format.js
      end
    end
  end

  def public
    @plans = Plan.public_visibility
    if params[:page] != 'all' then
      unless params[:s].blank? || params[:e].blank?
        @plans = @plans.letter_range(params[:s], params[:e])
      end
      unless params[:q].blank? then
        terms = params[:q].split.map {|t| "%#{t}%"}
        @plans = @plans.joins(:institution).joins(:users).where.
          any_of(["plans.name LIKE ?", terms],
                 ["institutions.full_name LIKE ?", terms],
                 ["users.last_name LIKE ? OR users.first_name LIKE ?", terms, terms])
      end
      @plans = @plans.page(params[:page]).per(10)
    else
      @plans = @plans.page(0).per(9999)
    end
  end

  def add_coowner_autocomplete
    u_name, = nil
    params.each do |k,v|
      u_name = v if k.end_with?('_name')
    end
    @item_description = params[:item_description]
    unless u_name.blank?
      u_name.split(',').each do |n|
        unless n.blank?
          m = n.match(/<?(\S+\@\S+\.[^ >]+)/)
          @user, @email = nil, nil
          @email = m[1] unless m.nil?
          @user = User.find_by(email: @email)
          if @user.nil?
            flash[:alert] = "The user you entered with email #{@email} was not found"
          elsif @user.user_plans.where(plan_id: @plan.id, owner: true).count > 0
            flash[:alert] = "The user chosen is the Owner of the Plan. An owner cannot be #{@item_description} for the same plan"
          elsif @user.user_plans.where(plan_id: @plan.id, owner: false).count > 0
            flash[:alert] = "The user you chose is already a #{@item_description}"
          else
            userplan = UserPlan.create(owner: false, user_id: @user.id, plan_id: @plan.id)
            userplan.save!
          end
        end
      end
    end
  end

  def delete_coowner
    @coowner = User.find(params[:coowner_id]) unless params[:coowner_id].nil?
    @plan = Plan.find(params[:plan_id]) unless params[:plan_id].nil?
    unless @coowner.nil?
      user_plan = UserPlan.where(user_id: @coowner.id, plan_id: @plan.id, owner: false).last
      user_plan.destroy
      respond_to do |format|
        format.html { redirect_to edit_plan_path(@plan), notice: "The selected Coowner associated with the Plan has been deleted successfully" }
        format.json { head :no_content }
      end
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_plan
      @plan = Plan.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def plan_params
      params.require(:plan).permit(:name, :requirements_template_id, :solicitation_identifier, :submission_deadline, :visibility, :current_plan_state_id)
    end

    def count
      @owned = @owned_plans.count
      @coowned = @coowned_plans.count
      @all = @owned + @coowned
      @approved = @plans.approved.count
      @submitted = @plans.submitted.count
      @committed = @plans.committed.count
      @rejected = @plans.rejected.count
    end

    def review_count
      @submitted = @submitted_plans.count
      @approved = @approved_plans.approved.count
      @rejected = @rejected_plans.rejected.count
      @all = @submitted + @approved + @rejected
    end

    def display_text(resource_contexts)
      resources = Array.new
      @resource_contexts.each do |resource_context|
        id  = resource_context.resource_id
        resource = Resource.find(id)
        if resource.resource_type == :help_text
          resources << resource
        end
      end
      return resources
    end

    def display_value(resource_contexts)
      resources = Array.new
      @resource_contexts.each do |resource_context|
        id  = resource_context.resource_id
        resource = Resource.find(id)
        if resource.resource_type == :actionable_url
          resources << resource
        end
      end
      return resources
    end

    def display_suggested(resource_contexts)
      resources = Array.new
      @resource_contexts.each do |resource_context|
        id  = resource_context.resource_id
        resource = Resource.find(id)
        if resource.resource_type == :suggested_response
          resources << resource
        end
      end
      return resources
    end

    def display_example(resource_contexts)
      resources = Array.new
      @resource_contexts.each do |resource_context|
        id  = resource_context.resource_id
        resource = Resource.find(id)
        if resource.resource_type == :example_response
          resources << resource
        end
      end
      return resources
    end

    def set_comments
      @comment = Comment.new
      comments = Comment.where(plan_id: @plan.id)
      @reviewer_comments = comments.reviewer_comments.order('created_at DESC')
      @owner_comments = comments.owner_comments.order('created_at DESC')
      @plan_states = @plan.plan_states
    end

    def coowners
      id = @plan.user_plans.where(owner: true).pluck(:user_id).first
      @owner = User.find(id)
      @coowners = Array.new
      user_plans = @plan.user_plans.where(owner: false)
      user_plans.each do |user_plan|
        id = user_plan.user_id
        @coowner = User.find(id)
        @coowners<< @coowner
      end
    end
end
