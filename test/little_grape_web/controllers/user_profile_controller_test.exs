defmodule LittleGrapeWeb.UserProfileControllerTest do
  use LittleGrapeWeb.ConnCase

  describe "GET /users/profile (edit)" do
    setup :register_and_log_in_user

    test "renders profile edit form", %{conn: conn} do
      conn = get(conn, ~p"/users/profile")

      response = html_response(conn, 200)
      # Check for form field names (language-agnostic)
      assert response =~ ~s(name="profile[first_name]")
      assert response =~ ~s(name="profile[last_name]")
      assert response =~ ~s(type="submit")
    end

    test "displays all profile form fields", %{conn: conn} do
      conn = get(conn, ~p"/users/profile")

      response = html_response(conn, 200)

      # Basic Info fields
      assert response =~ ~s(name="profile[first_name]")
      assert response =~ ~s(name="profile[last_name]")
      assert response =~ ~s(name="profile[birthdate]")
      assert response =~ ~s(name="profile[gender]")
      assert response =~ ~s(name="profile[city]")
      assert response =~ ~s(name="profile[country]")

      # About Me fields
      assert response =~ ~s(name="profile[bio]")
      assert response =~ ~s(name="profile[occupation]")

      # Lifestyle fields
      assert response =~ ~s(name="profile[smoking]")
      assert response =~ ~s(name="profile[drinking]")
      assert response =~ ~s(name="profile[has_children]")
      assert response =~ ~s(name="profile[wants_children]")

      # Background fields
      assert response =~ ~s(name="profile[education]")
      assert response =~ ~s(name="profile[religion]")
      assert response =~ ~s(name="profile[languages][]")

      # Physical Attributes fields
      assert response =~ ~s(name="profile[height_cm]")
      assert response =~ ~s(name="profile[body_type]")
      assert response =~ ~s(name="profile[eye_color]")
      assert response =~ ~s(name="profile[hair_color]")

      # Preferences fields
      assert response =~ ~s(name="profile[looking_for]")
      assert response =~ ~s(name="profile[preferred_gender]")
      assert response =~ ~s(name="profile[preferred_age_min]")
      assert response =~ ~s(name="profile[preferred_age_max]")
      assert response =~ ~s(name="profile[preferred_country]")

      # Interests fields
      assert response =~ ~s(name="profile[interests][]")
    end

    test "displays dropdown options for gender", %{conn: conn} do
      conn = get(conn, ~p"/users/profile")

      response = html_response(conn, 200)
      # Check for option values (language-agnostic)
      assert response =~ ~s(value="male")
      assert response =~ ~s(value="female")
    end

    test "displays dropdown options for smoking", %{conn: conn} do
      conn = get(conn, ~p"/users/profile")

      response = html_response(conn, 200)
      # Check for option values (language-agnostic)
      assert response =~ ~s(value="non_smoker")
      assert response =~ ~s(value="occasional")
      assert response =~ ~s(value="regular")
    end

    test "displays dropdown options for drinking", %{conn: conn} do
      conn = get(conn, ~p"/users/profile")

      response = html_response(conn, 200)
      # Check for option values (language-agnostic)
      assert response =~ ~s(value="non_drinker")
      assert response =~ ~s(value="social")
    end

    test "displays dropdown options for education", %{conn: conn} do
      conn = get(conn, ~p"/users/profile")

      response = html_response(conn, 200)
      # Check for option values (language-agnostic)
      assert response =~ ~s(value="high_school")
      assert response =~ ~s(value="bachelors")
      assert response =~ ~s(value="doctorate")
    end

    test "displays dropdown options for religion", %{conn: conn} do
      conn = get(conn, ~p"/users/profile")

      response = html_response(conn, 200)
      # Check for option values (language-agnostic)
      assert response =~ ~s(value="muslim")
      assert response =~ ~s(value="orthodox")
      assert response =~ ~s(value="catholic")
      assert response =~ ~s(value="atheist")
    end

    test "displays language checkboxes", %{conn: conn} do
      conn = get(conn, ~p"/users/profile")

      response = html_response(conn, 200)
      # Check for option values (language-agnostic)
      assert response =~ ~s(value="sq")
      assert response =~ ~s(value="en")
      assert response =~ ~s(value="it")
      assert response =~ ~s(value="de")
      assert response =~ ~s(value="fr")
    end

    test "displays interest checkboxes", %{conn: conn} do
      conn = get(conn, ~p"/users/profile")

      response = html_response(conn, 200)
      # Check for option values (language-agnostic)
      assert response =~ ~s(value="sports")
      assert response =~ ~s(value="music")
      assert response =~ ~s(value="travel")
      assert response =~ ~s(value="technology")
    end
  end

  describe "GET /users/profile (edit) - unauthenticated" do
    test "redirects to login page", %{conn: conn} do
      conn = get(conn, ~p"/users/profile")

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "PUT /users/profile (update)" do
    setup :register_and_log_in_user

    test "updates profile with valid data and redirects", %{conn: conn} do
      profile_params = %{
        "first_name" => "Jane",
        "last_name" => "Smith",
        "gender" => "female",
        "city" => "Pristina",
        "country" => "XK",
        "bio" => "A wonderful person",
        "occupation" => "Teacher",
        "height_cm" => "165",
        "body_type" => "slim",
        "eye_color" => "blue",
        "hair_color" => "blonde",
        "looking_for" => "relationship",
        "smoking" => "non_smoker",
        "drinking" => "non_drinker",
        "has_children" => "false",
        "wants_children" => "yes",
        "education" => "masters",
        "religion" => "orthodox",
        "languages" => ["sq", "en", "it"],
        "interests" => ["music", "travel", "reading"],
        "preferred_gender" => "male",
        "preferred_age_min" => "28",
        "preferred_age_max" => "40",
        "preferred_country" => "XK"
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      assert redirected_to(conn) == ~p"/users/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Profile updated successfully"

      # Verify the data was saved
      conn = get(conn, ~p"/users/profile")
      response = html_response(conn, 200)
      assert response =~ "Jane"
      assert response =~ "Smith"
    end

    test "updates profile with lifestyle fields", %{conn: conn} do
      profile_params = %{
        "smoking" => "occasional",
        "drinking" => "social",
        "has_children" => "true",
        "wants_children" => "have_and_want_more"
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      assert redirected_to(conn) == ~p"/users/profile"
    end

    test "updates profile with background fields", %{conn: conn} do
      profile_params = %{
        "education" => "doctorate",
        "religion" => "catholic",
        "languages" => ["sq", "en", "de", "fr"]
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      assert redirected_to(conn) == ~p"/users/profile"
    end

    test "updates profile with other_languages when other is selected", %{conn: conn} do
      profile_params = %{
        "languages" => ["sq", "en", "other"],
        "other_languages" => "Greek, Spanish, Portuguese"
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      assert redirected_to(conn) == ~p"/users/profile"

      # Verify the data was saved
      conn = get(conn, ~p"/users/profile")
      response = html_response(conn, 200)
      assert response =~ "Greek, Spanish, Portuguese"
    end

    test "updates profile with multiple interests", %{conn: conn} do
      profile_params = %{
        "interests" => ["sports", "music", "travel", "cooking", "fitness", "technology"]
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      assert redirected_to(conn) == ~p"/users/profile"
    end

    test "renders errors for invalid gender", %{conn: conn} do
      profile_params = %{
        "gender" => "invalid"
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      response = html_response(conn, 200)
      assert response =~ "is invalid"
    end

    test "renders errors for invalid country", %{conn: conn} do
      profile_params = %{
        "country" => "XX"
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      response = html_response(conn, 200)
      assert response =~ "is invalid"
    end

    test "renders errors for first_name too long", %{conn: conn} do
      too_long = String.duplicate("a", 51)

      profile_params = %{
        "first_name" => too_long
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      response = html_response(conn, 200)
      assert response =~ "should be at most 50 character(s)"
    end

    test "renders errors for bio too long", %{conn: conn} do
      too_long = String.duplicate("a", 1001)

      profile_params = %{
        "bio" => too_long
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      response = html_response(conn, 200)
      assert response =~ "should be at most 1000 character(s)"
    end

    test "renders errors for height_cm out of range", %{conn: conn} do
      profile_params = %{
        "height_cm" => "50"
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      response = html_response(conn, 200)
      assert response =~ "must be greater than 100"
    end

    test "renders errors for preferred_age_min under 18", %{conn: conn} do
      profile_params = %{
        "preferred_age_min" => "17"
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      response = html_response(conn, 200)
      assert response =~ "must be greater than or equal to 18"
    end

    test "renders errors for invalid smoking option", %{conn: conn} do
      profile_params = %{
        "smoking" => "invalid"
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      response = html_response(conn, 200)
      assert response =~ "is invalid"
    end

    test "renders errors for invalid drinking option", %{conn: conn} do
      profile_params = %{
        "drinking" => "invalid"
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      response = html_response(conn, 200)
      assert response =~ "is invalid"
    end

    test "renders errors for invalid education option", %{conn: conn} do
      profile_params = %{
        "education" => "invalid"
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      response = html_response(conn, 200)
      assert response =~ "is invalid"
    end

    test "renders errors for invalid religion option", %{conn: conn} do
      profile_params = %{
        "religion" => "invalid"
      }

      conn = put(conn, ~p"/users/profile", %{"profile" => profile_params})

      response = html_response(conn, 200)
      assert response =~ "is invalid"
    end
  end

  describe "PUT /users/profile (update) - unauthenticated" do
    test "redirects to login page", %{conn: conn} do
      conn = put(conn, ~p"/users/profile", %{"profile" => %{}})

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "DELETE /users/profile/picture" do
    setup :register_and_log_in_user

    test "redirects even when no picture exists", %{conn: conn} do
      conn = delete(conn, ~p"/users/profile/picture")

      assert redirected_to(conn) == ~p"/users/profile"
    end
  end

  describe "DELETE /users/profile/picture - unauthenticated" do
    test "redirects to login page", %{conn: conn} do
      conn = delete(conn, ~p"/users/profile/picture")

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
