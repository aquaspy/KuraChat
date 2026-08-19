module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = User.find_by(id: request.session[:user_id])
      reject_unauthorized_connection unless current_user
      unlocked_at = request.session[:unlocked_at]
      reject_unauthorized_connection unless unlocked_at && Time.zone.parse(unlocked_at.to_s) > Locking::IDLE_AFTER.ago
    end
  end
end
