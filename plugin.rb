# name: discourse-ekklesia
# about: provides Ekklesia eDemocracy platform features for Discourse
# version: 0.2.0
# url: https://github.com/edemocracy
# authors: Tobias dpausp <dpausp@posteo.de>
# required_version: 1.6

load File.expand_path('../lib/omniauth-ekklesia.rb', __FILE__)

# If you don't allow other login methods (only via Ekklesia ID server), then the sign-up button can be hidden like that:
#
#    .sign-up-button {
#      display: none !important;
#    }
#
# (put this CSS in: Admin Area -> Customize -> CSS/HTML -> your style -> CSS)


# XXX: don't know if disabling works for auth providers, check discourse code
enabled_site_setting :ekklesia_enabled

# add the following line somewhere in the code to open an interactive pry session in the current frame
#require 'pry'; binding.pry

# Discourse OAuth2 authenticator using the Ekklesia omniauth strategy.
# Following environment vars must be set:
# * EKKLESIA_CLIENT_SECRET
# * EKKLESIA_SITE_URL
#
# EKKLESIA_CLIENT_ID defaults to 'discourse' if not set
#
class EkklesiaAuthenticator < ::Auth::Authenticator
  CLIENT_ID = ENV.fetch('EKKLESIA_CLIENT_ID', 'discourse')
  CLIENT_SECRET = ENV.fetch('EKKLESIA_CLIENT_SECRET')
  SITE_URL = ENV.fetch('EKKLESIA_SITE_URL')

  def register_middleware(omniauth)
    omniauth.provider(
      :ekklesia,
      CLIENT_ID,
      CLIENT_SECRET,
      client_options: { site: SITE_URL }
    )
    Rails.logger.info("registered ekklesia authenticator for #{SITE_URL} ,"\
      "client_id #{CLIENT_ID}")
  end

  def name
    'ekklesia'
  end

  def initialize(opts = {})
    @opts = opts
  end

  def after_authenticate(auth_token)
    #require 'pry'; binding.pry
    data = auth_token[:info]
    extra = auth_token[:extra][:raw_info]
    auid = auth_token[:uid]
    user_type = extra[:type]

    result = Auth::Result.new
    result.name = data[:nickname]

    user_id = ::PluginStore.get(name, "auid_#{auid}")

    if user_id
      result.user = user = User.where(id: user_id).first
      if user
        change_user_trust_level(user, user_type)
      end
    end

    result.extra_data = { auid: auid, type: user_type }

    # only for development: supply valid mail adress to skip mail confirmation
    #result.email = 'fake@adress.is'
    #result.email_valid = true
    result
  end

  def change_user_trust_level(user, user_type)
    # increase trust level to level granted by ekklesia auth
    if user_type == "guest"
      lvl = SiteSetting.ekklesia_auto_trust_level_guest
    elsif user_type == "plain member"
      lvl = SiteSetting.ekklesia_auto_trust_level_plain_member
    elsif user_type == "eligible member"
      lvl = SiteSetting.ekklesia_auto_trust_level_eligible_member
    elsif user_type == "system user"
      lvl = SiteSetting.ekklesia_auto_trust_level_system_user
    end

    user.update_attribute(:trust_level, lvl)
  end

  def after_create_account(user, auth)
    auid = auth[:extra_data][:auid]
    user_type = auth[:extra_data][:type]
    ::PluginStore.set(name, "auid_#{auid}", user.id)
    if user_type == "eligible member" or user_type == "system user"
      auto_group = Group.where(name: SiteSetting.ekklesia_auto_group).first
      user.groups << auto_group if auto_group
    end
    # XXX: saving the user obj recalculates the password hash. This leads to unintended email token invalidation.
    # remove raw password in user object to avoid recalculation.
    user.instance_variable_set(:@raw_password, nil)
    change_user_trust_level(user, user_type)
    user
  end
end

auth_provider(
  title_setting: "ekklesia_login_button_title",
  enabled_setting: "ekklesia_enabled",
  message: 'Log in!',
  frame_width: 920,
  frame_height: 800,
  authenticator: EkklesiaAuthenticator.new
)

register_css <<CSS

.btn-social.ekklesia {
  background: rgb(253, 195, 0);
  color: black;
}

/* try to match the look of a normal link for the password change link which is in the wrong div */

a.change-id-password {
  font-size: inherit !important;
  color: #0088cc !important;
}

.change-id-password i {
  font-size: inherit !important;
  color: inherit !important;
}
CSS
