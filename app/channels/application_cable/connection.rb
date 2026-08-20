module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = User.find_by(id: request.session[:user_id])
      reject_unauthorized_connection unless current_user
      reject_unauthorized_connection unless Locking.session_open?(request.session, current_user)
    end
  end
end
