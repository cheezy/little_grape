defmodule LittleGrapeWeb.DiscoverLiveTest do
  use LittleGrapeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LittleGrape.AccountsFixtures

  alias LittleGrape.Accounts.Profile
  alias LittleGrape.Repo

  # Helper to set profile_picture (required for complete profile)
  defp set_profile_picture(profile) do
    profile
    |> Profile.profile_picture_changeset(%{profile_picture: "/uploads/test.jpg"})
    |> Repo.update!()
  end

  describe "DiscoverLive" do
    setup :register_and_log_in_user

    test "redirects to profile if profile is incomplete", %{conn: conn, user: user} do
      # User has no profile data set
      _profile = LittleGrape.Accounts.get_or_create_profile(user)

      {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/discover")

      assert path == "/users/profile"
      assert flash["error"] == "Please complete your profile before discovering matches."
    end

    test "mounts successfully with complete profile", %{conn: conn, user: user} do
      # Create a complete profile with picture
      profile_fixture(user) |> set_profile_picture()

      {:ok, _view, html} = live(conn, ~p"/discover")

      assert html =~ "Discover"
    end

    test "displays no profiles message when no candidates available", %{conn: conn, user: user} do
      # Create a complete profile with picture
      profile_fixture(user) |> set_profile_picture()

      {:ok, _view, html} = live(conn, ~p"/discover")

      assert html =~ "No more profiles to show"
      assert html =~ "Check back later for new matches"
    end

    test "displays profile card when candidates exist", %{conn: conn, user: user} do
      # Create complete profile for current user with picture
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create another user with complete profile that matches preferences
      other_user = user_fixture()

      profile_fixture(other_user, %{
        first_name: "Jane",
        gender: "female",
        preferred_gender: "male",
        city: "Tirana",
        country: "AL"
      })
      |> set_profile_picture()

      {:ok, _view, html} = live(conn, ~p"/discover")

      assert html =~ "Jane"
      assert html =~ "Tirana"
    end

    test "displays age on profile card", %{conn: conn, user: user} do
      # Create complete profile for current user with picture
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create another user with complete profile
      other_user = user_fixture()
      # Set birthdate to be 25 years ago
      birthdate = Date.add(Date.utc_today(), -25 * 365)

      profile_fixture(other_user, %{
        first_name: "Jane",
        gender: "female",
        preferred_gender: "male",
        birthdate: birthdate
      })
      |> set_profile_picture()

      {:ok, _view, html} = live(conn, ~p"/discover")

      assert html =~ "Jane"
      # Age should be approximately 25 (could be 24 or 25 depending on day)
      assert html =~ ~r/Jane.*2[45]/s
    end

    test "requires authentication", %{conn: _conn} do
      # Test with unauthenticated connection
      conn = build_conn()

      result = get(conn, ~p"/discover")

      assert redirected_to(result) == ~p"/users/log-in"
    end
  end
end
