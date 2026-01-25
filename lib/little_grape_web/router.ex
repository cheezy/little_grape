defmodule LittleGrapeWeb.Router do
  use LittleGrapeWeb, :router

  import LittleGrapeWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LittleGrapeWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; img-src 'self' data:; style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net"
    }

    plug :fetch_current_scope_for_user
    plug LittleGrapeWeb.Plugs.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LittleGrapeWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", LittleGrapeWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:little_grape, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LittleGrapeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", LittleGrapeWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", LittleGrapeWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings/email", UserSettingsController, :edit_email
    put "/users/settings/email", UserSettingsController, :update_email
    get "/users/settings/email/confirm/:token", UserSettingsController, :confirm_email
    get "/users/settings/password", UserSettingsController, :edit_password
    put "/users/settings/password", UserSettingsController, :update_password

    get "/users/profile", UserProfileController, :edit
    put "/users/profile", UserProfileController, :update
    delete "/users/profile/picture", UserProfileController, :delete_picture
  end

  scope "/", LittleGrapeWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
