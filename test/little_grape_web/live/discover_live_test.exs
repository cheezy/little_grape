defmodule LittleGrapeWeb.DiscoverLiveTest do
  use LittleGrapeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LittleGrape.AccountsFixtures

  alias LittleGrape.Accounts.Profile
  alias LittleGrape.Matches
  alias LittleGrape.Repo
  alias LittleGrape.Swipes

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

      assert html =~ "No more profiles right now"
      assert html =~ "broadening your preferences"
      assert html =~ "Update Preferences"
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

    test "clicking like records swipe and advances to next card", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create two candidates with unique names
      candidate1 = user_fixture()

      profile_fixture(candidate1, %{
        first_name: "FirstCandidate",
        gender: "female",
        preferred_gender: "male"
      })
      |> set_profile_picture()

      candidate2 = user_fixture()

      profile_fixture(candidate2, %{
        first_name: "SecondCandidate",
        gender: "female",
        preferred_gender: "male"
      })
      |> set_profile_picture()

      {:ok, view, html} = live(conn, ~p"/discover")

      # Find which candidate is shown first
      {first_candidate, second_candidate} =
        if html =~ "FirstCandidate" do
          {candidate1, candidate2}
        else
          {candidate2, candidate1}
        end

      first_name = if first_candidate == candidate1, do: "FirstCandidate", else: "SecondCandidate"

      second_name =
        if second_candidate == candidate1, do: "FirstCandidate", else: "SecondCandidate"

      assert html =~ first_name

      # Click like
      html = view |> element("button[phx-value-action=like]") |> render_click()

      # Should have recorded the swipe
      assert Swipes.has_swiped?(user.id, first_candidate.id)

      # Should advance to next candidate
      assert html =~ second_name
      refute html =~ first_name
    end

    test "clicking pass records swipe and advances to next card", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create two candidates with unique names
      candidate1 = user_fixture()

      profile_fixture(candidate1, %{
        first_name: "PassFirst",
        gender: "female",
        preferred_gender: "male"
      })
      |> set_profile_picture()

      candidate2 = user_fixture()

      profile_fixture(candidate2, %{
        first_name: "PassSecond",
        gender: "female",
        preferred_gender: "male"
      })
      |> set_profile_picture()

      {:ok, view, html} = live(conn, ~p"/discover")

      # Find which candidate is shown first
      {first_candidate, _second_candidate} =
        if html =~ "PassFirst" do
          {candidate1, candidate2}
        else
          {candidate2, candidate1}
        end

      first_name = if first_candidate == candidate1, do: "PassFirst", else: "PassSecond"
      second_name = if first_candidate == candidate1, do: "PassSecond", else: "PassFirst"

      assert html =~ first_name

      # Click pass
      html = view |> element("button[phx-value-action=pass]") |> render_click()

      # Should have recorded the swipe as pass
      swipe = Swipes.get_swipe(user.id, first_candidate.id)
      assert swipe.action == "pass"

      # Should advance to next candidate
      assert html =~ second_name
      refute html =~ first_name
    end

    test "mutual like creates match and shows modal", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create a candidate who already liked the current user
      candidate = user_fixture()

      profile_fixture(candidate, %{
        first_name: "MatchCandidate",
        gender: "female",
        preferred_gender: "male"
      })
      |> set_profile_picture()

      # Candidate already liked the user
      {:ok, _swipe} = Swipes.create_swipe(candidate, user.id, "like")

      {:ok, view, _html} = live(conn, ~p"/discover")

      # Click like - should create a match
      html = view |> element("button[phx-value-action=like]") |> render_click()

      # Should show match modal with photo, name, and buttons
      assert html =~ "a Match"
      assert html =~ "MatchCandidate"
      assert html =~ "liked each other"
      assert html =~ "Send Message"
      assert html =~ "Keep Swiping"
      # Modal should include profile photo
      assert html =~ "/uploads/test.jpg"

      # Should have created a match
      matches = Matches.list_matches(user)
      assert length(matches) == 1
    end

    test "shows no profiles message when last candidate is swiped", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create only one candidate
      candidate = user_fixture()

      profile_fixture(candidate, %{
        first_name: "Jane",
        gender: "female",
        preferred_gender: "male"
      })
      |> set_profile_picture()

      {:ok, view, _html} = live(conn, ~p"/discover")

      # Click pass on the only candidate
      html = view |> element("button[phx-value-action=pass]") |> render_click()

      # Should show no profiles message with suggestion
      assert html =~ "No more profiles right now"
      assert html =~ "broadening your preferences"
    end

    test "close match modal button works", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create a candidate who already liked the current user
      candidate = user_fixture()

      profile_fixture(candidate, %{
        first_name: "CloseModalCandidate",
        gender: "female",
        preferred_gender: "male"
      })
      |> set_profile_picture()

      # Candidate already liked the user
      {:ok, _swipe} = Swipes.create_swipe(candidate, user.id, "like")

      {:ok, view, _html} = live(conn, ~p"/discover")

      # Click like to trigger match
      html = view |> element("button[phx-value-action=like]") |> render_click()
      assert html =~ "a Match"

      # Close the modal
      html = view |> element("button", "Keep Swiping") |> render_click()
      refute html =~ "a Match"
    end
  end
end
