defmodule LittleGrapeWeb.ProfileOptionsTest do
  use ExUnit.Case, async: true

  alias LittleGrapeWeb.ProfileOptions

  setup do
    # The app's default locale is Albanian; pin English so labels are stable
    Gettext.put_locale(LittleGrapeWeb.Gettext, "en")
    :ok
  end

  describe "translate_language/1" do
    test "translates known language codes" do
      assert ProfileOptions.translate_language("en") == "English"
      assert ProfileOptions.translate_language("sq") == "Albanian"
      assert ProfileOptions.translate_language("other") == "Other"
    end

    test "passes unknown codes through unchanged" do
      assert ProfileOptions.translate_language("xx") == "xx"
    end

    test "covers every code in Profile.language_options/0" do
      for code <- LittleGrape.Accounts.Profile.language_options() do
        label = ProfileOptions.translate_language(code)
        assert is_binary(label)
        # Every option code has a real label (the catch-all echoes the code)
        refute label == code
      end
    end
  end
end
