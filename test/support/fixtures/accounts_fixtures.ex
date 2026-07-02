defmodule LittleGrape.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `LittleGrape.Accounts` context.
  """

  import Ecto.Query

  alias LittleGrape.Accounts
  alias LittleGrape.Accounts.Profile
  alias LittleGrape.Accounts.Scope
  alias LittleGrape.Repo

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "Password1!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token, %{password: valid_user_password()})

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Accounts.UserToken
    |> from(where: [token: ^token])
    |> LittleGrape.Repo.update_all(set: [authenticated_at: authenticated_at])
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    LittleGrape.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt =
      :second
      |> DateTime.utc_now()
      |> DateTime.add(amount_to_add, unit)

    Accounts.UserToken
    |> from(where: [token: ^token])
    |> LittleGrape.Repo.update_all(set: [inserted_at: dt, authenticated_at: dt])
  end

  # Profile fixtures

  def valid_profile_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      first_name: "John",
      last_name: "Doe",
      birthdate: ~D[1990-05-15],
      gender: "male",
      city: "Tirana",
      country: "AL",
      bio: "A friendly person looking for meaningful connections.",
      occupation: "Software Developer",
      height_cm: 175,
      body_type: "athletic",
      eye_color: "brown",
      hair_color: "black",
      looking_for: "relationship",
      smoking: "non_smoker",
      drinking: "social",
      has_children: false,
      wants_children: "maybe",
      education: "bachelors",
      religion: "muslim",
      languages: ["sq", "en"],
      interests: ["sports", "travel", "technology"],
      preferred_gender: "female",
      preferred_age_min: 25,
      preferred_age_max: 35,
      preferred_country: "AL"
    })
  end

  def profile_fixture(user, attrs \\ %{}) do
    {:ok, profile} = Accounts.get_or_create_profile(user)

    {:ok, profile} =
      Accounts.update_profile(profile, valid_profile_attributes(attrs))

    profile
  end

  @doc "Sets profile_picture via its dedicated changeset (required for a complete profile)."
  def set_profile_picture(profile) do
    profile
    |> Profile.profile_picture_changeset(%{profile_picture: "/uploads/test.jpg"})
    |> Repo.update!()
  end

  @doc """
  Creates a user with a complete profile (all required fields plus a picture),
  returning the user with `:profile` preloaded.
  """
  def create_user_with_complete_profile(attrs \\ %{}) do
    user = user_fixture()

    # Separate profile_picture from other attrs since it has a separate changeset
    {profile_picture, profile_attrs} =
      Map.pop(attrs, :profile_picture, "https://example.com/photo.jpg")

    profile_attrs =
      Map.merge(
        %{
          first_name: "Test",
          birthdate: ~D[1990-01-01],
          gender: "male",
          preferred_gender: "female"
        },
        profile_attrs
      )

    # Use Accounts context to properly create/update profile
    {:ok, profile} = Accounts.get_or_create_profile(user)
    {:ok, profile} = Accounts.update_profile(profile, profile_attrs)

    # Update profile picture separately using profile_picture_changeset
    if profile_picture do
      profile
      |> Profile.profile_picture_changeset(%{profile_picture: profile_picture})
      |> Repo.update!()
    end

    Repo.preload(user, :profile, force: true)
  end
end
