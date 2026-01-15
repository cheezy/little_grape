defmodule LittleGrapeWeb.UserSessionController do
  use LittleGrapeWeb, :controller

  alias LittleGrape.Accounts
  alias LittleGrapeWeb.UserAuth

  def new(conn, _params) do
    email = get_in(conn.assigns, [:current_scope, Access.key(:user), Access.key(:email)])
    form = Phoenix.Component.to_form(%{"email" => email}, as: "user")

    render(conn, :new, form: form)
  end

  # magic link login
  def create(conn, %{"user" => %{"token" => token} = user_params} = params) do
    info = confirmation_message(params)
    password_params = Map.take(user_params, ["password", "password_confirmation"])

    case Accounts.login_user_by_magic_link(token, password_params) do
      {:ok, {user, _expired_tokens}} ->
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_password_error(conn, token, changeset)

      {:error, :not_found} ->
        render_token_error(conn)
    end
  end

  # email + password login
  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, user_params)
    else
      form = Phoenix.Component.to_form(user_params, as: "user")

      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> render(:new, form: form)
    end
  end

  # magic link request
  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    conn
    |> put_flash(:info, info)
    |> redirect(to: ~p"/users/log-in")
  end

  def confirm(conn, %{"token" => token}) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = Phoenix.Component.to_form(%{"token" => token}, as: "user")

      conn
      |> assign(:user, user)
      |> assign(:form, form)
      |> render(:confirm)
    else
      conn
      |> put_flash(:error, "Magic link is invalid or it has expired.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  defp confirmation_message(%{"_action" => "confirmed"}), do: "User confirmed successfully."
  defp confirmation_message(_params), do: "Welcome back!"

  defp render_password_error(conn, token, changeset) do
    user = Accounts.get_user_by_magic_link_token(token)
    form = Phoenix.Component.to_form(%{"token" => token}, as: "user")

    conn
    |> assign(:user, user)
    |> assign(:form, form)
    |> assign(:changeset, changeset)
    |> put_flash(:error, format_changeset_errors(changeset))
    |> render(:confirm)
  end

  defp render_token_error(conn) do
    conn
    |> put_flash(:error, "The link is invalid or it has expired.")
    |> render(:new, form: Phoenix.Component.to_form(%{}, as: "user"))
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(". ", fn {field, errors} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(errors, ", ")}"
    end)
  end
end
