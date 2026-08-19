namespace :kura do
  desc "List users (id, email, chats, created)"
  task users: :environment do
    if User.none?
      puts "No users."
      next
    end

    puts format("%-4s  %-36s  %5s  %s", "id", "email", "chats", "created")
    User.order(:id).each do |user|
      puts format("%-4s  %-36s  %5s  %s",
        user.id,
        user.email,
        user.conversations.count,
        user.created_at.utc.strftime("%Y-%m-%d %H:%M"))
    end
  end

  desc "Create a user: rake kura:create EMAIL=you@x.com PASSWORD=secret-password"
  task create: :environment do
    email = ENV["EMAIL"].to_s.strip
    password = ENV["PASSWORD"].to_s
    abort "EMAIL= and PASSWORD= are required (min 8 chars)." if email.blank? || password.length < 8

    user = User.new(email: email, password: password, password_confirmation: password)
    abort user.errors.full_messages.to_sentence unless user.save
    puts "Created #{user.email} (id #{user.id})."
  end

  desc "Reset a password: rake kura:password EMAIL=you@x.com PASSWORD=new-secret"
  task password: :environment do
    email = ENV["EMAIL"].to_s.strip
    password = ENV["PASSWORD"].to_s
    abort "EMAIL= and PASSWORD= are required (min 8 chars)." if email.blank? || password.length < 8

    user = User.find_by(email: email.downcase)
    abort "No user with email #{email}." unless user

    user.password = password
    user.password_confirmation = password
    abort user.errors.full_messages.to_sentence unless user.save
    puts "Password updated for #{user.email}."
  end
end
