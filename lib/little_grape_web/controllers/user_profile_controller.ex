defmodule LittleGrapeWeb.UserProfileController do
  use LittleGrapeWeb, :controller

  alias LittleGrape.Accounts
  alias LittleGrape.Accounts.Profile

  def edit(conn, _params) do
    user = conn.assigns.current_scope.user
    profile = Accounts.get_or_create_profile(user)
    changeset = Accounts.change_profile(profile)

    render(conn, :edit, [profile: profile, changeset: changeset] ++ profile_options())
  end

  def update(conn, %{"profile" => profile_params}) do
    user = conn.assigns.current_scope.user
    profile = Accounts.get_or_create_profile(user)

    # Handle profile picture upload separately
    {picture_upload, profile_params} = Map.pop(profile_params, "profile_picture")

    with {:ok, profile} <- Accounts.update_profile(profile, profile_params),
         {:ok, _profile} <- handle_picture_upload(profile, picture_upload) do
      conn
      |> put_flash(:info, "Profile updated successfully.")
      |> redirect(to: ~p"/users/profile")
    else
      {:error, changeset} ->
        render(conn, :edit, [profile: profile, changeset: changeset] ++ profile_options())
    end
  end

  def delete_picture(conn, _params) do
    user = conn.assigns.current_scope.user
    profile = Accounts.get_or_create_profile(user)

    case Accounts.delete_profile_picture(profile) do
      {:ok, _profile} ->
        conn
        |> put_flash(:info, "Profile picture removed.")
        |> redirect(to: ~p"/users/profile")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to remove profile picture.")
        |> redirect(to: ~p"/users/profile")
    end
  end

  defp handle_picture_upload(profile, %Plug.Upload{} = upload) do
    Accounts.update_profile_picture(profile, upload)
  end

  defp handle_picture_upload(profile, _), do: {:ok, profile}

  defp profile_options do
    [
      gender_options: Profile.gender_options(),
      country_options: Profile.country_options(),
      body_type_options: Profile.body_type_options(),
      eye_color_options: Profile.eye_color_options(),
      hair_color_options: Profile.hair_color_options(),
      looking_for_options: Profile.looking_for_options(),
      smoking_options: Profile.smoking_options(),
      drinking_options: Profile.drinking_options(),
      wants_children_options: Profile.wants_children_options(),
      education_options: Profile.education_options(),
      religion_options: Profile.religion_options(),
      language_options: Profile.language_options(),
      interest_options: Profile.interest_options()
    ]
  end
end
