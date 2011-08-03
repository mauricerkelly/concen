require "rack/gridfs"

# Use Rails.application.routes.prepend on Rails 3.1.
Rails.application.routes.draw do
  match "/visits/record.gif" => "control_center/visits#record", :as => "record_visit"
  match "/visits/js" => "control_center/visits#visit_recorder_js", :as => "visit_recorder_js"
  mount Rack::GridFS::Endpoint.new(:db => Mongoid.database, :lookup => :path, :expires => 315360000), :at => "gridfs"

  scope :constraints => {:subdomain => "controlcenter"}, :module => "control_center", :as => "control_center"  do
    get "signout" => "sessions#destroy", :as => "signout"
    get "signin" => "sessions#new", :as => "signin"
    get "signup" => "users#new", :as => "signup"

    resources :users
    resources :sessions
    resources :responses
    resource :status do
      member do
        get :server
        get :count
      end
    end
    resources :visits do
      collection do
        get :count
        get :pages
      end
    end
    resources :pages do
      collection do
        put :sort
      end
      resources :grid_files do
        collection do
          post :upload
        end
      end
    end

    root :to => "visits#index"
  end
end
