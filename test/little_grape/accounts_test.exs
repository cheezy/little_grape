defmodule LittleGrape.AccountsTest do
  use LittleGrape.DataCase

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Accounts
  alias LittleGrape.Accounts.Profile
  alias LittleGrape.Accounts.User
  alias LittleGrape.Accounts.UserToken

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture() |> set_password()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users without password" do
      email = unique_user_email()
      attrs = valid_user_attributes(email: email)
      {:ok, user} = Accounts.register_user(attrs)
      assert user.email == email
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "NewValid1!"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "NewValid1!"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "short",
          password_confirmation: "another"
        })

      assert "should be at least 8 character(s)" in errors_on(changeset).password
      assert "does not match password" in errors_on(changeset).password_confirmation
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "NewValid1!"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "NewValid1!")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "NewValid1!"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      authenticated_at =
        :second
        |> DateTime.utc_now()
        |> DateTime.add(-3600)

      user = %{user | authenticated_at: authenticated_at}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_magic_link_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "confirms user and expires tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, [%{token: ^hashed_token}]}} =
               Accounts.login_user_by_magic_link(encoded_token, %{password: valid_user_password()})

      assert user.confirmed_at
    end

    test "returns user and (deleted) token for confirmed user" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {^user, []}} = Accounts.login_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed user has password set" do
      user = unconfirmed_user_fixture()
      {1, nil} = Repo.update_all(User, set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Accounts.login_user_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  ## Profile Tests

  describe "get_profile/1" do
    test "returns nil if the profile doesn't exist" do
      user = user_fixture()
      refute Accounts.get_profile(user)
    end

    test "returns the profile if it exists" do
      user = user_fixture()
      _profile = profile_fixture(user)

      assert %Profile{} = Accounts.get_profile(user)
    end
  end

  describe "get_or_create_profile/1" do
    test "creates a new profile if one doesn't exist" do
      user = user_fixture()
      refute Accounts.get_profile(user)

      profile = Accounts.get_or_create_profile(user)

      assert %Profile{} = profile
      assert profile.user_id == user.id
    end

    test "returns existing profile if one exists" do
      user = user_fixture()
      existing_profile = Accounts.get_or_create_profile(user)

      # Update the profile so we can verify it's the same one
      {:ok, updated_profile} =
        Accounts.update_profile(existing_profile, %{first_name: "Test"})

      fetched_profile = Accounts.get_or_create_profile(user)

      assert fetched_profile.id == updated_profile.id
      assert fetched_profile.first_name == "Test"
    end
  end

  describe "change_profile/2" do
    test "returns a profile changeset" do
      user = user_fixture()
      profile = Accounts.get_or_create_profile(user)

      assert %Ecto.Changeset{} = Accounts.change_profile(profile)
    end
  end

  describe "update_profile/2" do
    setup do
      user = user_fixture()
      profile = Accounts.get_or_create_profile(user)
      %{user: user, profile: profile}
    end

    test "updates profile with valid data", %{profile: profile} do
      attrs = valid_profile_attributes()

      assert {:ok, updated_profile} = Accounts.update_profile(profile, attrs)
      assert updated_profile.first_name == "John"
      assert updated_profile.last_name == "Doe"
      assert updated_profile.gender == "male"
      assert updated_profile.country == "AL"
      assert updated_profile.smoking == "non_smoker"
      assert updated_profile.drinking == "social"
      assert updated_profile.education == "bachelors"
      assert updated_profile.religion == "muslim"
      assert updated_profile.languages == ["sq", "en"]
      assert updated_profile.interests == ["sports", "travel", "technology"]
    end

    test "validates first_name max length", %{profile: profile} do
      too_long = String.duplicate("a", 51)
      {:error, changeset} = Accounts.update_profile(profile, %{first_name: too_long})

      assert "should be at most 50 character(s)" in errors_on(changeset).first_name
    end

    test "validates last_name max length", %{profile: profile} do
      too_long = String.duplicate("a", 51)
      {:error, changeset} = Accounts.update_profile(profile, %{last_name: too_long})

      assert "should be at most 50 character(s)" in errors_on(changeset).last_name
    end

    test "validates bio max length", %{profile: profile} do
      too_long = String.duplicate("a", 1001)
      {:error, changeset} = Accounts.update_profile(profile, %{bio: too_long})

      assert "should be at most 1000 character(s)" in errors_on(changeset).bio
    end

    test "validates gender is one of the allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{gender: "invalid"})

      assert "is invalid" in errors_on(changeset).gender
    end

    test "validates country is one of the allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{country: "XX"})

      assert "is invalid" in errors_on(changeset).country
    end

    test "validates body_type is one of the allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{body_type: "invalid"})

      assert "is invalid" in errors_on(changeset).body_type
    end

    test "validates eye_color is one of the allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{eye_color: "invalid"})

      assert "is invalid" in errors_on(changeset).eye_color
    end

    test "validates hair_color is one of the allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{hair_color: "invalid"})

      assert "is invalid" in errors_on(changeset).hair_color
    end

    test "validates looking_for is one of the allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{looking_for: "invalid"})

      assert "is invalid" in errors_on(changeset).looking_for
    end

    test "validates smoking is one of the allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{smoking: "invalid"})

      assert "is invalid" in errors_on(changeset).smoking
    end

    test "validates drinking is one of the allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{drinking: "invalid"})

      assert "is invalid" in errors_on(changeset).drinking
    end

    test "validates wants_children is one of the allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{wants_children: "invalid"})

      assert "is invalid" in errors_on(changeset).wants_children
    end

    test "validates education is one of the allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{education: "invalid"})

      assert "is invalid" in errors_on(changeset).education
    end

    test "validates religion is one of the allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{religion: "invalid"})

      assert "is invalid" in errors_on(changeset).religion
    end

    test "validates languages is a subset of allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{languages: ["invalid"]})

      assert "has an invalid entry" in errors_on(changeset).languages
    end

    test "validates interests is a subset of allowed options", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{interests: ["invalid"]})

      assert "has an invalid entry" in errors_on(changeset).interests
    end

    test "validates height_cm is within range", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{height_cm: 50})
      assert "must be greater than 100" in errors_on(changeset).height_cm

      {:error, changeset} = Accounts.update_profile(profile, %{height_cm: 300})
      assert "must be less than 250" in errors_on(changeset).height_cm
    end

    test "validates preferred_age_min is at least 18", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{preferred_age_min: 17})

      assert "must be greater than or equal to 18" in errors_on(changeset).preferred_age_min
    end

    test "validates preferred_age_max is at least 18", %{profile: profile} do
      {:error, changeset} = Accounts.update_profile(profile, %{preferred_age_max: 17})

      assert "must be greater than or equal to 18" in errors_on(changeset).preferred_age_max
    end

    test "validates preferred_age_max is greater than preferred_age_min", %{profile: profile} do
      {:error, changeset} =
        Accounts.update_profile(profile, %{preferred_age_min: 30, preferred_age_max: 25})

      assert "must be greater than or equal to minimum age" in errors_on(changeset).preferred_age_max
    end

    test "validates birthdate must be at least 18 years old", %{profile: profile} do
      too_young = Date.add(Date.utc_today(), -17 * 365)
      {:error, changeset} = Accounts.update_profile(profile, %{birthdate: too_young})

      assert "you must be at least 18 years old" in errors_on(changeset).birthdate
    end

    test "validates birthdate is not too far in the past", %{profile: profile} do
      too_old = Date.add(Date.utc_today(), -101 * 365)
      {:error, changeset} = Accounts.update_profile(profile, %{birthdate: too_old})

      assert "is too far in the past" in errors_on(changeset).birthdate
    end

    test "validates other_languages max length", %{profile: profile} do
      too_long = String.duplicate("a", 256)
      {:error, changeset} = Accounts.update_profile(profile, %{other_languages: too_long})

      assert "should be at most 255 character(s)" in errors_on(changeset).other_languages
    end

    test "accepts valid other_languages", %{profile: profile} do
      {:ok, updated_profile} =
        Accounts.update_profile(profile, %{
          languages: ["sq", "en", "other"],
          other_languages: "Greek, Spanish"
        })

      assert "other" in updated_profile.languages
      assert updated_profile.other_languages == "Greek, Spanish"
    end
  end

  describe "Profile.gender_options/0" do
    test "returns the list of gender options" do
      assert Profile.gender_options() == ["male", "female", "other"]
    end
  end

  describe "Profile.country_options/0" do
    test "returns the list of country options" do
      options = Profile.country_options()
      assert "AL" in options
      assert "XK" in options
      assert "other" in options
    end
  end

  describe "Profile.smoking_options/0" do
    test "returns the list of smoking options" do
      assert Profile.smoking_options() == ["non_smoker", "occasional", "regular"]
    end
  end

  describe "Profile.drinking_options/0" do
    test "returns the list of drinking options" do
      assert Profile.drinking_options() == ["non_drinker", "social", "regular"]
    end
  end

  describe "Profile.wants_children_options/0" do
    test "returns the list of wants_children options" do
      assert Profile.wants_children_options() == ["yes", "no", "maybe", "have_and_want_more"]
    end
  end

  describe "Profile.education_options/0" do
    test "returns the list of education options" do
      options = Profile.education_options()
      assert "high_school" in options
      assert "bachelors" in options
      assert "doctorate" in options
    end
  end

  describe "Profile.religion_options/0" do
    test "returns the list of religion options" do
      options = Profile.religion_options()
      assert "muslim" in options
      assert "orthodox" in options
      assert "prefer_not_to_say" in options
    end
  end

  describe "Profile.language_options/0" do
    test "returns the list of language options" do
      options = Profile.language_options()
      assert "sq" in options
      assert "en" in options
      assert "other" in options
    end
  end

  describe "Profile.interest_options/0" do
    test "returns the list of interest options" do
      options = Profile.interest_options()
      assert "sports" in options
      assert "travel" in options
      assert "technology" in options
    end
  end
end
