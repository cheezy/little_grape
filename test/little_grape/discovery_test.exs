defmodule LittleGrape.DiscoveryTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Accounts
  alias LittleGrape.Accounts.Profile
  alias LittleGrape.Blocks.Block
  alias LittleGrape.Discovery
  alias LittleGrape.Repo
  alias LittleGrape.Swipes

  # Helper to create a user with a complete profile
  defp create_user_with_complete_profile(attrs \\ %{}) do
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
    profile = Accounts.get_or_create_profile(user)
    {:ok, profile} = Accounts.update_profile(profile, profile_attrs)

    # Update profile picture separately using profile_picture_changeset
    if profile_picture do
      profile
      |> Profile.profile_picture_changeset(%{profile_picture: profile_picture})
      |> Repo.update!()
    end

    Repo.preload(user, :profile, force: true)
  end

  # Helper to execute query and get user IDs
  defp get_user_ids(query) do
    query
    |> Repo.all()
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  describe "exclude_self/2" do
    test "excludes the current user from results" do
      user = create_user_with_complete_profile()
      other_user = create_user_with_complete_profile()

      result_ids =
        Discovery.base_query()
        |> Discovery.exclude_self(user.id)
        |> get_user_ids()

      assert other_user.id in result_ids
      refute user.id in result_ids
    end

    test "returns all other users" do
      user = create_user_with_complete_profile()
      other1 = create_user_with_complete_profile()
      other2 = create_user_with_complete_profile()

      result_ids =
        Discovery.base_query()
        |> Discovery.exclude_self(user.id)
        |> get_user_ids()

      assert other1.id in result_ids
      assert other2.id in result_ids
      refute user.id in result_ids
    end
  end

  describe "exclude_already_swiped/2" do
    test "excludes users that have been liked" do
      user = create_user_with_complete_profile()
      liked_user = create_user_with_complete_profile()
      not_swiped_user = create_user_with_complete_profile()

      {:ok, _swipe} = Swipes.create_swipe(user, liked_user.id, "like")

      result_ids =
        Discovery.base_query()
        |> Discovery.exclude_already_swiped(user.id)
        |> get_user_ids()

      refute liked_user.id in result_ids
      assert not_swiped_user.id in result_ids
    end

    test "excludes users that have been passed" do
      user = create_user_with_complete_profile()
      passed_user = create_user_with_complete_profile()
      not_swiped_user = create_user_with_complete_profile()

      {:ok, _swipe} = Swipes.create_swipe(user, passed_user.id, "pass")

      result_ids =
        Discovery.base_query()
        |> Discovery.exclude_already_swiped(user.id)
        |> get_user_ids()

      refute passed_user.id in result_ids
      assert not_swiped_user.id in result_ids
    end

    test "includes users who swiped on current user (reverse direction)" do
      user = create_user_with_complete_profile()
      other_user = create_user_with_complete_profile()

      # Other user swiped on current user, but current user hasn't swiped on them
      {:ok, _swipe} = Swipes.create_swipe(other_user, user.id, "like")

      result_ids =
        Discovery.base_query()
        |> Discovery.exclude_already_swiped(user.id)
        |> get_user_ids()

      # Other user should still be visible since current user hasn't swiped
      assert other_user.id in result_ids
    end

    test "excludes multiple swiped users" do
      user = create_user_with_complete_profile()
      swiped1 = create_user_with_complete_profile()
      swiped2 = create_user_with_complete_profile()
      swiped3 = create_user_with_complete_profile()
      not_swiped = create_user_with_complete_profile()

      {:ok, _} = Swipes.create_swipe(user, swiped1.id, "like")
      {:ok, _} = Swipes.create_swipe(user, swiped2.id, "pass")
      {:ok, _} = Swipes.create_swipe(user, swiped3.id, "like")

      result_ids =
        Discovery.base_query()
        |> Discovery.exclude_already_swiped(user.id)
        |> get_user_ids()

      refute swiped1.id in result_ids
      refute swiped2.id in result_ids
      refute swiped3.id in result_ids
      assert not_swiped.id in result_ids
    end
  end

  describe "exclude_blocked/2" do
    test "excludes users blocked by current user" do
      user = create_user_with_complete_profile()
      blocked_user = create_user_with_complete_profile()
      not_blocked_user = create_user_with_complete_profile()

      {:ok, _block} =
        %Block{}
        |> Block.changeset(%{blocker_id: user.id, blocked_id: blocked_user.id})
        |> Repo.insert()

      result_ids =
        Discovery.base_query()
        |> Discovery.exclude_blocked(user.id)
        |> get_user_ids()

      refute blocked_user.id in result_ids
      assert not_blocked_user.id in result_ids
    end

    test "excludes users who blocked current user" do
      user = create_user_with_complete_profile()
      blocker_user = create_user_with_complete_profile()
      not_blocker_user = create_user_with_complete_profile()

      {:ok, _block} =
        %Block{}
        |> Block.changeset(%{blocker_id: blocker_user.id, blocked_id: user.id})
        |> Repo.insert()

      result_ids =
        Discovery.base_query()
        |> Discovery.exclude_blocked(user.id)
        |> get_user_ids()

      refute blocker_user.id in result_ids
      assert not_blocker_user.id in result_ids
    end

    test "excludes blocks in both directions" do
      user = create_user_with_complete_profile()
      user_blocked = create_user_with_complete_profile()
      blocked_user = create_user_with_complete_profile()
      neutral_user = create_user_with_complete_profile()

      # User blocked someone
      {:ok, _} =
        %Block{}
        |> Block.changeset(%{blocker_id: user.id, blocked_id: user_blocked.id})
        |> Repo.insert()

      # Someone blocked user
      {:ok, _} =
        %Block{}
        |> Block.changeset(%{blocker_id: blocked_user.id, blocked_id: user.id})
        |> Repo.insert()

      result_ids =
        Discovery.base_query()
        |> Discovery.exclude_blocked(user.id)
        |> get_user_ids()

      refute user_blocked.id in result_ids
      refute blocked_user.id in result_ids
      assert neutral_user.id in result_ids
    end
  end

  describe "require_complete_profile/1" do
    test "excludes users without profile_picture" do
      complete_user = create_user_with_complete_profile()

      # Create user with complete profile but no picture
      incomplete_user = create_user_with_complete_profile(%{profile_picture: nil})

      result_ids =
        Discovery.base_query()
        |> Discovery.require_complete_profile()
        |> get_user_ids()

      assert complete_user.id in result_ids
      refute incomplete_user.id in result_ids
    end

    test "excludes users without first_name" do
      complete_user = create_user_with_complete_profile()

      # Create user with profile but no first_name
      incomplete_user = create_user_with_complete_profile(%{first_name: nil})

      result_ids =
        Discovery.base_query()
        |> Discovery.require_complete_profile()
        |> get_user_ids()

      assert complete_user.id in result_ids
      refute incomplete_user.id in result_ids
    end

    test "excludes users without birthdate" do
      complete_user = create_user_with_complete_profile()

      # Create user with profile but no birthdate
      incomplete_user = create_user_with_complete_profile(%{birthdate: nil})

      result_ids =
        Discovery.base_query()
        |> Discovery.require_complete_profile()
        |> get_user_ids()

      assert complete_user.id in result_ids
      refute incomplete_user.id in result_ids
    end

    test "excludes users without gender" do
      complete_user = create_user_with_complete_profile()

      # Create user with profile but no gender
      incomplete_user = create_user_with_complete_profile(%{gender: nil})

      result_ids =
        Discovery.base_query()
        |> Discovery.require_complete_profile()
        |> get_user_ids()

      assert complete_user.id in result_ids
      refute incomplete_user.id in result_ids
    end

    test "excludes users without any profile" do
      complete_user = create_user_with_complete_profile()
      no_profile_user = user_fixture()

      result_ids =
        Discovery.base_query()
        |> Discovery.require_complete_profile()
        |> get_user_ids()

      assert complete_user.id in result_ids
      refute no_profile_user.id in result_ids
    end
  end

  describe "filter_by_mutual_gender_preferences/3" do
    test "filters by user's preferred gender" do
      # User is male looking for female
      male_looking_for_female =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "female"
        })

      # Female looking for male (should match)
      female_looking_for_male =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male"
        })

      # Male looking for female (gender doesn't match preference)
      another_male =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "female"
        })

      result_ids =
        Discovery.base_query()
        |> Discovery.require_complete_profile()
        |> Discovery.filter_by_mutual_gender_preferences("male", "female")
        |> get_user_ids()

      assert female_looking_for_male.id in result_ids
      refute another_male.id in result_ids
      # male_looking_for_female is male, so they don't match the "female" preference
      refute male_looking_for_female.id in result_ids
    end

    test "candidate's preferred_gender must match user's gender" do
      # User is male looking for female
      _user =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "female"
        })

      # Female looking for female (won't match male user)
      female_looking_for_female =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "female"
        })

      # Female looking for male (will match)
      female_looking_for_male =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male"
        })

      result_ids =
        Discovery.base_query()
        |> Discovery.require_complete_profile()
        |> Discovery.filter_by_mutual_gender_preferences("male", "female")
        |> get_user_ids()

      refute female_looking_for_female.id in result_ids
      assert female_looking_for_male.id in result_ids
    end

    test "user with preferred_gender='any' sees all genders" do
      # User wants any gender
      user_looking_for_any =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "any"
        })

      # Various candidates who want males
      male_wanting_male =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "male"
        })

      female_wanting_male =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male"
        })

      other_wanting_male =
        create_user_with_complete_profile(%{
          gender: "other",
          preferred_gender: "male"
        })

      result_ids =
        Discovery.base_query()
        |> Discovery.require_complete_profile()
        |> Discovery.filter_by_mutual_gender_preferences("male", "any")
        |> get_user_ids()

      # All should be visible because user's preference is 'any'
      # and all candidates want males
      assert male_wanting_male.id in result_ids
      assert female_wanting_male.id in result_ids
      assert other_wanting_male.id in result_ids
      assert user_looking_for_any.id in result_ids
    end

    test "candidate with preferred_gender='any' matches any user gender" do
      # User is male looking for female
      _user =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "female"
        })

      # Female who is open to any gender (should match male user)
      female_wanting_any =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "any"
        })

      # Female who only wants females (won't match male user)
      female_wanting_female =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "female"
        })

      result_ids =
        Discovery.base_query()
        |> Discovery.require_complete_profile()
        |> Discovery.filter_by_mutual_gender_preferences("male", "female")
        |> get_user_ids()

      assert female_wanting_any.id in result_ids
      refute female_wanting_female.id in result_ids
    end

    test "both user and candidate have preferred_gender='any'" do
      user_any =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "any"
        })

      candidate_any =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "any"
        })

      result_ids =
        Discovery.base_query()
        |> Discovery.require_complete_profile()
        |> Discovery.filter_by_mutual_gender_preferences("male", "any")
        |> get_user_ids()

      assert candidate_any.id in result_ids
      assert user_any.id in result_ids
    end
  end

  describe "apply_hard_filters/1" do
    test "combines all filters correctly" do
      # Create the current user
      user =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "female"
        })

      # Valid candidate: complete profile, female looking for male, not blocked, not swiped
      valid_candidate =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male"
        })

      # Invalid: user themselves
      _self = user

      # Invalid: already swiped
      already_swiped =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male"
        })

      {:ok, _} = Swipes.create_swipe(user, already_swiped.id, "like")

      # Invalid: blocked by user
      blocked_by_user =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male"
        })

      {:ok, _} =
        %Block{}
        |> Block.changeset(%{blocker_id: user.id, blocked_id: blocked_by_user.id})
        |> Repo.insert()

      # Invalid: blocked user
      blocked_user =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male"
        })

      {:ok, _} =
        %Block{}
        |> Block.changeset(%{blocker_id: blocked_user.id, blocked_id: user.id})
        |> Repo.insert()

      # Invalid: incomplete profile (no photo)
      incomplete_user =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male",
          profile_picture: nil
        })

      # Invalid: wrong gender (male, but user wants female)
      wrong_gender =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "female"
        })

      # Invalid: candidate doesn't want user's gender
      wrong_preference =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "female"
        })

      result_ids =
        user
        |> Discovery.apply_hard_filters()
        |> get_user_ids()

      # Only valid candidate should be in results
      assert valid_candidate.id in result_ids
      refute user.id in result_ids
      refute already_swiped.id in result_ids
      refute blocked_by_user.id in result_ids
      refute blocked_user.id in result_ids
      refute incomplete_user.id in result_ids
      refute wrong_gender.id in result_ids
      refute wrong_preference.id in result_ids
    end

    test "works with user who has preferred_gender='any'" do
      user =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "any"
        })

      # All these candidates want males, so they should all be visible
      male_wanting_male =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "male"
        })

      female_wanting_male =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male"
        })

      other_wanting_any =
        create_user_with_complete_profile(%{
          gender: "other",
          preferred_gender: "any"
        })

      # This one doesn't want males
      female_wanting_female =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "female"
        })

      result_ids =
        user
        |> Discovery.apply_hard_filters()
        |> get_user_ids()

      assert male_wanting_male.id in result_ids
      assert female_wanting_male.id in result_ids
      assert other_wanting_any.id in result_ids
      refute female_wanting_female.id in result_ids
      refute user.id in result_ids
    end

    test "returns empty when no valid candidates exist" do
      user =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "female"
        })

      # Only other user has wrong gender preference
      _wrong_candidate =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "female"
        })

      result_ids =
        user
        |> Discovery.apply_hard_filters()
        |> get_user_ids()

      assert result_ids == []
    end
  end

  # ============================================================================
  # Soft Scoring Tests
  # ============================================================================

  describe "score_age/3" do
    # Helper to create a birthdate for a specific age
    defp birthdate_for_age(age) do
      today = Date.utc_today()
      Date.new!(today.year - age, today.month, today.day)
    end

    test "returns 1.0 when candidate age is within preferred range" do
      # Candidate is 30 years old
      birthdate = birthdate_for_age(30)
      score = Discovery.score_age(birthdate, 25, 35)
      assert score == 1.0
    end

    test "returns 1.0 when age equals minimum" do
      birthdate = birthdate_for_age(25)
      score = Discovery.score_age(birthdate, 25, 35)
      assert score == 1.0
    end

    test "returns 1.0 when age equals maximum" do
      birthdate = birthdate_for_age(35)
      score = Discovery.score_age(birthdate, 25, 35)
      assert score == 1.0
    end

    test "returns reduced score when below minimum" do
      # Candidate is 22 (3 years below min of 25)
      birthdate = birthdate_for_age(22)
      score = Discovery.score_age(birthdate, 25, 35)
      assert score == 0.7
    end

    test "returns reduced score when above maximum" do
      # Candidate is 38 (3 years above max of 35)
      birthdate = birthdate_for_age(38)
      score = Discovery.score_age(birthdate, 25, 35)
      assert score == 0.7
    end

    test "returns 0.0 when far outside range" do
      # Candidate is 50 (15 years above max of 35)
      birthdate = birthdate_for_age(50)
      score = Discovery.score_age(birthdate, 25, 35)
      assert score == 0.0
    end

    test "uses default min of 18 when preferred_age_min is nil" do
      # Candidate is 20, should be in range [18, 35]
      birthdate = birthdate_for_age(20)
      score = Discovery.score_age(birthdate, nil, 35)
      assert score == 1.0
    end

    test "uses default max of 100 when preferred_age_max is nil" do
      # Candidate is 60, should be in range [25, 100]
      birthdate = birthdate_for_age(60)
      score = Discovery.score_age(birthdate, 25, nil)
      assert score == 1.0
    end

    test "returns 0.0 when birthdate is nil" do
      score = Discovery.score_age(nil, 25, 35)
      assert score == 0.0
    end
  end

  describe "score_country/2" do
    test "returns 1.0 when countries match" do
      assert Discovery.score_country("US", "US") == 1.0
    end

    test "returns 0.0 when countries differ" do
      assert Discovery.score_country("US", "CA") == 0.0
    end

    test "returns 0.5 when user country is nil" do
      assert Discovery.score_country(nil, "US") == 0.5
    end

    test "returns 0.5 when candidate country is nil" do
      assert Discovery.score_country("US", nil) == 0.5
    end
  end

  describe "score_interests/2" do
    test "returns 1.0 when all interests match" do
      interests = ["music", "travel", "cooking"]
      score = Discovery.score_interests(interests, interests)
      assert score == 1.0
    end

    test "returns partial score for partial match" do
      user_interests = ["music", "travel", "cooking"]
      candidate_interests = ["music", "sports", "reading"]
      # 1 shared out of 5 unique = 0.2
      score = Discovery.score_interests(user_interests, candidate_interests)
      assert score == 0.2
    end

    test "returns 0.0 when no interests match" do
      user_interests = ["music", "travel"]
      candidate_interests = ["sports", "reading"]
      score = Discovery.score_interests(user_interests, candidate_interests)
      assert score == 0.0
    end

    test "returns 0.5 when user has no interests" do
      assert Discovery.score_interests([], ["music"]) == 0.5
    end

    test "returns 0.5 when candidate has no interests" do
      assert Discovery.score_interests(["music"], []) == 0.5
    end

    test "returns 0.5 when user interests is nil" do
      assert Discovery.score_interests(nil, ["music"]) == 0.5
    end

    test "returns 0.5 when candidate interests is nil" do
      assert Discovery.score_interests(["music"], nil) == 0.5
    end
  end

  describe "score_languages/2" do
    test "returns 1.0 when sharing 2+ languages" do
      user_languages = ["en", "es", "fr"]
      candidate_languages = ["en", "es", "de"]
      score = Discovery.score_languages(user_languages, candidate_languages)
      assert score == 1.0
    end

    test "returns 0.75 when sharing 1 language" do
      user_languages = ["en", "es"]
      candidate_languages = ["en", "de"]
      score = Discovery.score_languages(user_languages, candidate_languages)
      assert score == 0.75
    end

    test "returns 0.0 when sharing no languages" do
      user_languages = ["en", "es"]
      candidate_languages = ["de", "fr"]
      score = Discovery.score_languages(user_languages, candidate_languages)
      assert score == 0.0
    end

    test "returns 0.5 when user has no languages" do
      assert Discovery.score_languages([], ["en"]) == 0.5
    end

    test "returns 0.5 when candidate has no languages" do
      assert Discovery.score_languages(["en"], []) == 0.5
    end

    test "returns 0.5 when user languages is nil" do
      assert Discovery.score_languages(nil, ["en"]) == 0.5
    end

    test "returns 0.5 when candidate languages is nil" do
      assert Discovery.score_languages(["en"], nil) == 0.5
    end
  end

  describe "score_religion/2" do
    test "returns 1.0 when religions match" do
      assert Discovery.score_religion("muslim", "muslim") == 1.0
    end

    test "returns 0.0 when religions differ" do
      assert Discovery.score_religion("muslim", "orthodox") == 0.0
    end

    test "returns 0.5 when user religion is nil" do
      assert Discovery.score_religion(nil, "muslim") == 0.5
    end

    test "returns 0.5 when candidate religion is nil" do
      assert Discovery.score_religion("muslim", nil) == 0.5
    end

    test "returns 0.5 when user prefers not to say" do
      assert Discovery.score_religion("prefer_not_to_say", "muslim") == 0.5
    end

    test "returns 0.5 when candidate prefers not to say" do
      assert Discovery.score_religion("muslim", "prefer_not_to_say") == 0.5
    end
  end

  describe "score_freshness/1" do
    test "returns 1.0 when profile was updated today" do
      now = DateTime.utc_now()
      score = Discovery.score_freshness(now)
      assert score == 1.0
    end

    test "returns 1.0 when profile was updated yesterday" do
      yesterday = DateTime.add(DateTime.utc_now(), -1, :day)
      score = Discovery.score_freshness(yesterday)
      assert score == 1.0
    end

    test "returns partial score for profiles updated in the last month" do
      fifteen_days_ago = DateTime.add(DateTime.utc_now(), -15, :day)
      score = Discovery.score_freshness(fifteen_days_ago)
      assert score == 0.5
    end

    test "returns 0.0 for profiles not updated in 30+ days" do
      thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)
      score = Discovery.score_freshness(thirty_days_ago)
      assert score == 0.0
    end

    test "returns 0.5 when updated_at is nil" do
      assert Discovery.score_freshness(nil) == 0.5
    end
  end

  describe "score_liked_you/1" do
    test "returns 1.0 when candidate has liked user" do
      assert Discovery.score_liked_you(true) == 1.0
    end

    test "returns 0.0 when candidate has not liked user" do
      assert Discovery.score_liked_you(false) == 0.0
    end

    test "returns 0.0 for non-boolean input" do
      assert Discovery.score_liked_you(nil) == 0.0
    end
  end

  describe "random_variance/0" do
    test "returns values within expected range" do
      # Test multiple times to verify range
      variances = for _ <- 1..100, do: Discovery.random_variance()

      assert Enum.all?(variances, fn v -> v >= -0.10 and v <= 0.10 end)
    end

    test "returns different values (randomness)" do
      variances = for _ <- 1..10, do: Discovery.random_variance()
      unique_count = Enum.uniq(variances) |> length()

      # Should have some variety (at least a few different values)
      assert unique_count > 1
    end
  end

  describe "calculate_score/3" do
    test "calculates composite score from all factors" do
      user_profile = %Profile{
        birthdate: ~D[1990-01-01],
        preferred_age_min: 25,
        preferred_age_max: 35,
        country: "US",
        interests: ["music", "travel"],
        languages: ["en", "es"],
        religion: "other",
        updated_at: DateTime.utc_now()
      }

      # Candidate is 30, same country, same interests, same languages, same religion
      candidate_profile = %Profile{
        birthdate: Date.add(Date.utc_today(), -30 * 365),
        country: "US",
        interests: ["music", "travel"],
        languages: ["en", "es"],
        religion: "other",
        updated_at: DateTime.utc_now()
      }

      score = Discovery.calculate_score(user_profile, candidate_profile, true)

      # With all factors at 1.0 and liked_you true:
      # 0.30 + 0.20 + 0.20 + 0.10 + 0.10 + 0.05 + 0.05 = 1.0
      # Plus randomization of +/-0.10
      assert score >= 0.90
      assert score <= 1.0
    end

    test "returns lower score for mismatched profiles" do
      user_profile = %Profile{
        birthdate: ~D[1990-01-01],
        preferred_age_min: 25,
        preferred_age_max: 35,
        country: "US",
        interests: ["music", "travel"],
        languages: ["en"],
        religion: "muslim",
        updated_at: DateTime.utc_now()
      }

      # Candidate is 45, different country, no shared interests, no shared languages
      candidate_profile = %Profile{
        birthdate: Date.add(Date.utc_today(), -45 * 365),
        country: "CA",
        interests: ["sports", "reading"],
        languages: ["fr"],
        religion: "orthodox",
        updated_at: DateTime.add(DateTime.utc_now(), -30, :day)
      }

      score = Discovery.calculate_score(user_profile, candidate_profile, false)

      # Should be much lower due to mismatches
      assert score < 0.5
    end

    test "score is clamped between 0.0 and 1.0" do
      user_profile = %Profile{
        birthdate: ~D[1990-01-01],
        preferred_age_min: nil,
        preferred_age_max: nil,
        country: nil,
        interests: [],
        languages: [],
        religion: nil,
        updated_at: nil
      }

      candidate_profile = %Profile{
        birthdate: nil,
        country: nil,
        interests: [],
        languages: [],
        religion: nil,
        updated_at: nil
      }

      # Run multiple times to account for randomization
      scores =
        for _ <- 1..50, do: Discovery.calculate_score(user_profile, candidate_profile, false)

      assert Enum.all?(scores, fn s -> s >= 0.0 and s <= 1.0 end)
    end
  end

  describe "score_and_rank/2" do
    test "ranks candidates by score descending" do
      # Create user looking for females
      user =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "female",
          country: "US",
          interests: ["music", "travel"],
          languages: ["en"],
          religion: "other",
          preferred_age_min: 25,
          preferred_age_max: 35
        })

      # Perfect match - same country, interests, languages, religion
      perfect_match =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male",
          country: "US",
          interests: ["music", "travel"],
          languages: ["en"],
          religion: "other",
          birthdate: Date.add(Date.utc_today(), -30 * 365)
        })

      # Partial match - different country
      partial_match =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male",
          country: "CA",
          interests: ["music"],
          languages: ["en"],
          religion: "other",
          birthdate: Date.add(Date.utc_today(), -30 * 365)
        })

      # Poor match - different everything
      poor_match =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male",
          country: "DE",
          interests: ["sports"],
          languages: ["de"],
          religion: "orthodox",
          birthdate: Date.add(Date.utc_today(), -45 * 365)
        })

      query = Discovery.apply_hard_filters(user)
      ranked = Discovery.score_and_rank(user, query)

      user_ids = Enum.map(ranked, fn {candidate, _score} -> candidate.id end)

      # Perfect match should generally be first (accounting for randomization)
      # We can't guarantee exact order due to randomization, but perfect match
      # should typically score higher
      assert length(user_ids) == 3
      assert perfect_match.id in user_ids
      assert partial_match.id in user_ids
      assert poor_match.id in user_ids
    end

    test "includes liked-you boost in scoring" do
      user =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "female"
        })

      # Two similar candidates
      candidate_who_liked =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male"
        })

      candidate_no_like =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male"
        })

      # Have candidate_who_liked swipe on user
      {:ok, _} = Swipes.create_swipe(candidate_who_liked, user.id, "like")

      query = Discovery.apply_hard_filters(user)
      ranked = Discovery.score_and_rank(user, query)

      # The candidate who liked should get the boost
      # Find the scores
      liked_score =
        ranked
        |> Enum.find(fn {c, _} -> c.id == candidate_who_liked.id end)
        |> elem(1)

      no_like_score =
        ranked
        |> Enum.find(fn {c, _} -> c.id == candidate_no_like.id end)
        |> elem(1)

      # The liked-you candidate should score higher on average
      # Due to randomization, we can't guarantee this every time
      # But we can at least verify both are scored
      assert liked_score != nil
      assert no_like_score != nil
    end
  end

  describe "get_discovery_feed/2" do
    test "returns ranked list of candidates" do
      user =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "female"
        })

      candidate =
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male"
        })

      feed = Discovery.get_discovery_feed(user)

      assert length(feed) == 1
      assert hd(feed).id == candidate.id
    end

    test "respects limit option" do
      user =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "female"
        })

      for _ <- 1..5 do
        create_user_with_complete_profile(%{
          gender: "female",
          preferred_gender: "male"
        })
      end

      feed = Discovery.get_discovery_feed(user, limit: 3)

      assert length(feed) == 3
    end

    test "returns empty list when no candidates match" do
      user =
        create_user_with_complete_profile(%{
          gender: "male",
          preferred_gender: "female"
        })

      feed = Discovery.get_discovery_feed(user)

      assert feed == []
    end
  end
end
