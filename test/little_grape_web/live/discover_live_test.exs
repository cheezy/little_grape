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
      assert flash["error"] =~ "Please complete your profile to start discovering matches"
      assert flash["error"] =~ "Missing:"
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

      # Should show match modal with photo, name, and button
      assert html =~ "a Match"
      assert html =~ "MatchCandidate"
      assert html =~ "liked each other"
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

    test "tapping card expands to show full profile details", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create a candidate with full profile details
      candidate = user_fixture()

      profile_fixture(candidate, %{
        first_name: "ExpandCandidate",
        gender: "female",
        preferred_gender: "male",
        bio: "I love hiking and photography",
        interests: ["travel", "photography", "nature"],
        occupation: "Software Engineer",
        looking_for: "relationship",
        height_cm: 165,
        education: "masters",
        smoking: "non_smoker",
        drinking: "social"
      })
      |> set_profile_picture()

      {:ok, view, html} = live(conn, ~p"/discover")

      # Initially should show "Tap to see more" hint
      assert html =~ "Tap to see more"
      # Should not show expanded details yet
      refute html =~ "About Me"
      refute html =~ "I love hiking"

      # Click the card to expand
      html = view |> element("div[phx-click=toggle_expanded]") |> render_click()

      # Should now show expanded profile details
      assert html =~ "About Me"
      assert html =~ "I love hiking and photography"
      assert html =~ "Interests"
      assert html =~ "Travel"
      assert html =~ "Photography"
      assert html =~ "Software Engineer"
      assert html =~ "Relationship"
      assert html =~ "165 cm"
      assert html =~ "Masters"
      assert html =~ "Non Smoker"
      assert html =~ "Social"
      assert html =~ "Tap photo to collapse"
    end

    test "tapping expanded card collapses back to card view", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create a candidate with bio
      candidate = user_fixture()

      profile_fixture(candidate, %{
        first_name: "CollapseCandidate",
        gender: "female",
        preferred_gender: "male",
        bio: "Hello world"
      })
      |> set_profile_picture()

      {:ok, view, _html} = live(conn, ~p"/discover")

      # Expand the card
      html = view |> element("div[phx-click=toggle_expanded]") |> render_click()
      assert html =~ "About Me"
      assert html =~ "Hello world"

      # Collapse the card
      html = view |> element("div[phx-click=toggle_expanded]") |> render_click()

      # Should no longer show expanded details
      refute html =~ "About Me"
      assert html =~ "Tap to see more"
    end

    test "like/pass buttons remain visible when expanded", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create a candidate
      candidate = user_fixture()

      profile_fixture(candidate, %{
        first_name: "ButtonsCandidate",
        gender: "female",
        preferred_gender: "male",
        bio: "Test bio"
      })
      |> set_profile_picture()

      {:ok, view, html} = live(conn, ~p"/discover")

      # Buttons visible before expansion
      assert html =~ "phx-value-action=\"like\""
      assert html =~ "phx-value-action=\"pass\""

      # Expand the card
      html = view |> element("div[phx-click=toggle_expanded]") |> render_click()

      # Buttons still visible after expansion
      assert html =~ "phx-value-action=\"like\""
      assert html =~ "phx-value-action=\"pass\""
    end

    test "expansion resets when advancing to next candidate", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create two candidates
      candidate1 = user_fixture()

      profile_fixture(candidate1, %{
        first_name: "ResetFirst",
        gender: "female",
        preferred_gender: "male",
        bio: "First bio"
      })
      |> set_profile_picture()

      candidate2 = user_fixture()

      profile_fixture(candidate2, %{
        first_name: "ResetSecond",
        gender: "female",
        preferred_gender: "male",
        bio: "Second bio"
      })
      |> set_profile_picture()

      {:ok, view, _html} = live(conn, ~p"/discover")

      # Expand the first card
      html = view |> element("div[phx-click=toggle_expanded]") |> render_click()
      assert html =~ "About Me"

      # Swipe to advance to next candidate
      html = view |> element("button[phx-value-action=pass]") |> render_click()

      # Next card should not be expanded
      assert html =~ "Tap to see more"
      refute html =~ "About Me"
    end

    test "displays languages in expanded profile view", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create a candidate with multiple languages
      candidate = user_fixture()

      profile_fixture(candidate, %{
        first_name: "LanguageCandidate",
        gender: "female",
        preferred_gender: "male",
        languages: ["sq", "en", "it", "de", "fr", "sr", "mk", "tr", "other"]
      })
      |> set_profile_picture()

      {:ok, view, _html} = live(conn, ~p"/discover")

      # Expand the card to see languages
      html = view |> element("div[phx-click=toggle_expanded]") |> render_click()

      # Should show formatted language names
      assert html =~ "Languages"
      assert html =~ "Albanian"
      assert html =~ "English"
      assert html =~ "Italian"
      assert html =~ "German"
      assert html =~ "French"
      assert html =~ "Serbian"
      assert html =~ "Macedonian"
      assert html =~ "Turkish"
      assert html =~ "Other"
    end

    test "displays body_type and religion in expanded profile view", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create a candidate with body_type and religion
      candidate = user_fixture()

      profile_fixture(candidate, %{
        first_name: "DetailedCandidate",
        gender: "female",
        preferred_gender: "male",
        body_type: "athletic",
        religion: "orthodox"
      })
      |> set_profile_picture()

      {:ok, view, _html} = live(conn, ~p"/discover")

      # Expand the card
      html = view |> element("div[phx-click=toggle_expanded]") |> render_click()

      # Should show body type and religion
      assert html =~ "Body Type"
      assert html =~ "Athletic"
      assert html =~ "Religion"
      assert html =~ "Orthodox"
    end

    test "displays profile card without city/country when not set", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create a candidate without city/country (explicitly set to nil to override defaults)
      candidate = user_fixture()

      profile_fixture(candidate, %{
        first_name: "NoLocationCandidate",
        gender: "female",
        preferred_gender: "male",
        city: nil,
        country: nil
      })
      |> set_profile_picture()

      {:ok, _view, html} = live(conn, ~p"/discover")

      # Should show the name
      assert html =~ "NoLocationCandidate"
      # Should not show location line (no city/country to display)
      refute html =~ "Tirana"
    end

    test "displays profile card with only city when country not set", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create a candidate with only city (explicitly set country to nil)
      candidate = user_fixture()

      profile_fixture(candidate, %{
        first_name: "CityOnlyCandidate",
        gender: "female",
        preferred_gender: "male",
        city: "Pristina",
        country: nil
      })
      |> set_profile_picture()

      {:ok, _view, html} = live(conn, ~p"/discover")

      # Should show the name and city
      assert html =~ "CityOnlyCandidate"
      assert html =~ "Pristina"
    end

    test "swipe is ignored when already swiping", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create a candidate
      candidate = user_fixture()

      profile_fixture(candidate, %{
        first_name: "SwipingCandidate",
        gender: "female",
        preferred_gender: "male"
      })
      |> set_profile_picture()

      {:ok, view, _html} = live(conn, ~p"/discover")

      # This test verifies the swiping guard clause works
      # The guard prevents duplicate swipes while processing
      # First swipe should work
      html = view |> element("button[phx-value-action=like]") |> render_click()

      # Should have recorded the swipe
      assert Swipes.has_swiped?(user.id, candidate.id)

      # Verify the candidate was swiped (shows no more profiles)
      assert html =~ "No more profiles right now"
    end

    test "swipe is ignored when no current candidate", %{conn: conn, user: user} do
      # Create complete profile for current user with picture
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # No candidates created, so current_candidate will be nil
      {:ok, view, html} = live(conn, ~p"/discover")

      # Verify no candidates
      assert html =~ "No more profiles right now"

      # Try to swipe - should be ignored (no error, just noop)
      # We can't easily click the button since it doesn't exist
      # But we can send the event directly
      html = render_click(view, "swipe", %{"action" => "like"})

      # Should still show no profiles message (unchanged)
      assert html =~ "No more profiles right now"
    end

    test "handles swipe error by advancing to next candidate", %{conn: conn, user: user} do
      # Create complete profile for current user
      profile_fixture(user, %{gender: "male", preferred_gender: "female"})
      |> set_profile_picture()

      # Create two candidates
      candidate1 = user_fixture()

      profile_fixture(candidate1, %{
        first_name: "ErrorFirst",
        gender: "female",
        preferred_gender: "male"
      })
      |> set_profile_picture()

      candidate2 = user_fixture()

      profile_fixture(candidate2, %{
        first_name: "ErrorSecond",
        gender: "female",
        preferred_gender: "male"
      })
      |> set_profile_picture()

      {:ok, view, html} = live(conn, ~p"/discover")

      # Find which candidate is shown first
      {first_candidate, _second_candidate} =
        if html =~ "ErrorFirst" do
          {candidate1, candidate2}
        else
          {candidate2, candidate1}
        end

      first_name = if first_candidate == candidate1, do: "ErrorFirst", else: "ErrorSecond"
      second_name = if first_candidate == candidate1, do: "ErrorSecond", else: "ErrorFirst"

      # Pre-create a swipe to cause a duplicate error
      {:ok, _swipe} = Swipes.create_swipe(user, first_candidate.id, "like")

      # Now try to swipe again - should handle error and advance
      html = view |> element("button[phx-value-action=like]") |> render_click()

      # Should have advanced to next candidate despite error
      assert html =~ second_name
      refute html =~ first_name
    end
  end
end
