# encoding: UTF-8
class AttendancesController < InheritedResources::Base
  belongs_to :registration_group, :optional => true

  actions :new, :create
  
  before_filter :load_registration_types
  before_filter :validate_free_registration, :only => [:create]
  
  def new
    new!
  end
  
  def create
    create! do |success, failure|
      success.html do
        begin
          flash[:notice] = t('flash.attendance.create.success')
          EmailNotifications.registration_pending(@attendance).deliver if @attendance.registration_fee > 0
          @attendance.email_sent = true
          @attendance.save
        rescue => ex
          notify_airbrake(ex)
          flash[:alert] = t('flash.attendance.mail.fail')
        end
        redirect_to attendance_status_path(@attendance)
      end
      failure.html do
        flash.now[:error] = t('flash.failure')
        render :new
      end
    end
  end

  def status
    @attendance = Attendance.find(params[:id])
  end
  
  private
  def build_resource
    attributes = params[:attendance]
    unless attributes
      attributes = current_user.attendance_attributes
      attributes[:email_confirmation] = current_user.email
      attributes[:gender] = current_user.gender
    end
    attributes[:event_id] = @event.id
    attributes[:user_id] = current_user.id
    if parent?
      attributes[:registration_type_id] = RegistrationType.find_by_title('registration_type.group').id
      attributes[:organization] = parent.name
    end
    if current_user.has_approved_session?(@event)
      attributes[:registration_type_id] = RegistrationType.find_by_title('registration_type.free').id
    end
    if @registration_types.size == 1
      attributes[:registration_type_id] = @registration_types.first.id
    end
    attributes[:registration_date] ||= Time.now
    @attendance ||= Attendance.new(attributes)
  end
  
  def load_registration_types
    @registration_types ||= valid_registration_types
  end

  def valid_registration_types
    registration_types = RegistrationType.without_free.without_group.all
    registration_types << RegistrationType.find_by_title('registration_type.free') if allowed_free_registration?
    registration_types
  end
    
  def validate_free_registration
    if is_free?(build_resource) && !allowed_free_registration?
      build_resource.errors[:registration_type_id] << t('activerecord.errors.models.attendance.attributes.registration_type_id.free_not_allowed')
      flash.now[:error] = t('flash.attendance.create.free_not_allowed') 
      render :new and return false
    end
    true
  end
  
  def is_free?(attendance)
    attendance.registration_type == RegistrationType.find_by_title('registration_type.free')
  end
  
  def allowed_free_registration?
    (current_user.has_approved_session?(@event) || current_user.organizer?) && !parent?
  end
end