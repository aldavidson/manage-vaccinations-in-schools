# frozen_string_literal: true

module ParentInterface
  class ConsentForms::EditController < ConsentForms::BaseController
    include WizardControllerConcern

    before_action :validate_params, only: %i[update]
    before_action :set_health_answer, if: :is_health_question_step?
    before_action :set_follow_up_changes_start_page, only: %i[show]

    HOME_EDUCATED_SCHOOL_ID = "home-educated"

    def show
      render_wizard
    end

    def update
      model = @consent_form

      model.wizard_step = current_step

      if is_health_question_step?
        @health_answer.assign_attributes(health_answer_params)
        model.health_question_number = @question_number
      elsif step == "school"
        school_id = update_params[:school_id]
        if school_id == HOME_EDUCATED_SCHOOL_ID
          model.school = nil
          model.education_setting = "home"
        else
          model.school_id = school_id
          model.education_setting = "school"
        end
      else
        model.assign_attributes(update_params)
      end

      if current_step == :parent
        if @consent_form.parental_responsibility == "no"
          redirect_to cannot_consent_responsibility_parent_interface_consent_form_path(
                        @consent_form
                      ) and return
        end

        if skip_to_confirm? && @consent_form.parent_phone_changed? &&
             @consent_form.parent_phone.present?
          jump_to("contact-method", skip_to_confirm: true)
        end
      elsif current_step == :consent
        @consent_form.seed_health_questions
      end

      set_steps # The wizard_steps can change after certain attrs change
      setup_wizard_translated # Next/previous steps can change after steps change

      skip_to_confirm_or_next_health_question

      render_wizard model
    end

    private

    def finish_wizard_path
      confirm_parent_interface_consent_form_path(@consent_form)
    end

    def update_params
      permitted_attributes = {
        name: %i[
          given_name
          family_name
          use_preferred_name
          preferred_given_name
          preferred_family_name
        ],
        date_of_birth: %i[
          date_of_birth(3i)
          date_of_birth(2i)
          date_of_birth(1i)
        ],
        confirm_school: %i[school_confirmed],
        education_setting: %i[education_setting],
        school: %i[school_id],
        parent: %i[
          parent_email
          parent_full_name
          parent_phone
          parent_phone_receive_updates
          parent_relationship_other_name
          parent_relationship_type
          parental_responsibility
        ],
        contact_method: %i[
          parent_contact_method_type
          parent_contact_method_other_details
        ],
        consent: %i[response chosen_vaccine],
        reason: %i[reason],
        reason_notes: %i[reason_notes],
        address: %i[address_line_1 address_line_2 address_town address_postcode]
      }.fetch(current_step)

      params.fetch(:consent_form, {}).permit(permitted_attributes)
    end

    def health_answer_params
      params.fetch(:health_answer, {}).permit(%i[response notes])
    end

    def set_steps
      # Translated steps are cached after running setup_wizard_translated.
      # To allow us to run this method multiple times during a single action
      # lifecycle, we need to clear the cache.
      @wizard_translations = nil

      self.steps = @consent_form.wizard_steps
    end

    def set_health_answer
      @question_number = params.fetch(:question_number, "0").to_i

      @health_answer = @consent_form.health_answers[@question_number]
    end

    def validate_params
      case current_step
      when :date_of_birth
        validator =
          DateParamsValidator.new(
            field_name: :date_of_birth,
            object: @consent_form,
            params: update_params
          )

        unless validator.date_params_valid?
          @consent_form.date_of_birth = validator.date_params_as_struct
          render_wizard nil, status: :unprocessable_entity
        end
      end
    end

    def is_health_question_step?
      step == "health-question"
    end

    def current_health_answer
      index = step.split("-").last.to_i - 1
      @consent_form.health_answers[index]
    end

    def skip_to_confirm?
      request.referer&.include?("skip_to_confirm") ||
        params.key?(:skip_to_confirm) ||
        session.key?(:follow_up_changes_start_page)
    end

    def next_health_question
      @next_health_question ||= @health_answer.next_health_answer_index
    end

    def next_health_answer_missing_response?
      if next_health_question
        @consent_form.health_answers[next_health_question].response.blank?
      else
        false
      end
    end

    def skip_to_confirm_or_next_health_question
      if skip_to_confirm?
        return if @skip_to.present? # already going somewhere else

        if is_health_question_step? && next_health_answer_missing_response?
          jump_to "health-question", question_number: next_health_question
        else
          jump_to Wicked::FINISH_STEP
        end
      elsif is_health_question_step? && next_health_question
        jump_to "health-question", question_number: next_health_question
      end
    end

    def set_follow_up_changes_start_page
      if params[:skip_to_confirm] && is_health_question_step?
        session[:follow_up_changes_start_page] = @question_number
      end
    end
  end
end
