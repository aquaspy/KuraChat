Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get  "signup", to: "registrations#new", as: :signup
  post "signup", to: "registrations#create"
  get  "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  get  "unlock", to: "locks#show", as: :unlock
  post "unlock", to: "locks#create"
  post "lock", to: "locks#lock", as: :lock

  resources :conversations, only: %i[index show create update destroy] do
    resource :share, only: %i[create update destroy]
    resources :messages, only: %i[create] do
      post :retry, on: :member
    end
  end
  get "s/:token", to: "shared_conversations#show", as: :shared_conversation, token: /[A-Za-z0-9_-]+/

  root "conversations#index"
end
