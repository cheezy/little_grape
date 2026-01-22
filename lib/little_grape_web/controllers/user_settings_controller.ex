defmodule LittleGrapeWeb.UserSettingsController do
  use LittleGrapeWeb, :controller

  alias LittleGrape.Accounts
  alias LittleGrapeWeb.UserAuth

  def edit_email(conn, _params) do
    user = conn.assigns.current_scope.user
    changeset = Accounts.change_user_email(user)
    render(conn, :edit_email, email_changeset: changeset)
  end

  def update_email(conn, %{"user" => user_params}) do
    user = conn.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        changeset
        |> Ecto.Changeset.apply_action!(:insert)
        |> Accounts.deliver_user_update_email_instructions(
          user.email,
          &url(~p"/users/settings/email/confirm/#{&1}")
        )

        conn
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> redirect(to: ~p"/users/settings/email")

      changeset ->
        render(conn, :edit_email, email_changeset: %{changeset | action: :insert})
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_scope.user, token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: ~p"/users/settings/email")

      {:error, _} ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/users/settings/email")
    end
  end

  def edit_password(conn, _params) do
    user = conn.assigns.current_scope.user
    changeset = Accounts.change_user_password(user)
    render(conn, :edit_password, password_changeset: changeset)
  end

  def update_password(conn, %{"user" => user_params}) do
    user = conn.assigns.current_scope.user

    case Accounts.update_user_password(user, user_params) do
      {:ok, {user, _}} ->
        conn
        |> put_flash(:info, "Password updated successfully.")
        |> put_session(:user_return_to, ~p"/users/settings/password")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, :edit_password, password_changeset: changeset)
    end
  end
end
