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
end
