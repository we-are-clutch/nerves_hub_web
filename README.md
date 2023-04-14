# nerves_hub_www

[![CircleCI](https://circleci.com/gh/nerves-hub/nerves_hub_web.svg?style=svg)](https://circleci.com/gh/nerves-hub/nerves_hub_web)

*This is the 2.0 development branch of NervesHubWeb. If you have been using
NervesHub prior to around April, 2023 and are not following 2.0 development, see
the [`maint-v1.0`
branch](https://github.com/nerves-hub/nerves_hub_web/tree/maint-v1.0)*

A domain independent back end solution for rolling out software updates to edge
devices connected to IP based networking infrastructure.

## Project overview and setup

### Development environment setup

For best compatibility with Erlang SSL versions, we use Erlang/OTP 23.0.4. If
you're coming to NervesHub without OTP 23 or earlier devices, don't worry about
this. OTP 23.0.4 is difficult to install on Apple M1/M2 hardware so developing
on Linux is highly recommended if you're keeping to the OTP 23.0.4 requirement.

The `.tool-versions` files contains the Erlang, Elixir and NodeJS versions.
Install [asdf-vm](https://asdf-vm.com/) and run the following for quick setup:

```sh
cd nerves_hub_web

asdf plugin-add nodejs
bash ~/.asdf/plugins/nodejs/bin/import-release-team-keyring # this requires gpg to be installed
asdf install
```

Modify the `.tool-versions` if you want to use a later version of Erlang.

You'll also need to install `fwup` and `xdelta3`. See the [fwup installation
instructions](https://github.com/fhunleth/fwup#installing) and the [xdelta3
instructions](https://github.com/jmacd/xdelta).


On Debian/Ubuntu, you will also need to install the following packages:

```sh
sudo apt install docker-compose inotify-tools
```

Local development uses the host `nerves-hub.org` for connections and cert
validation. To properly map to your local running server, you'll need to add a
host record for it:

```sh
echo "127.0.0.1 nerves-hub.org" | sudo tee -a /etc/hosts
```

### First time application setup

1. Setup database connection

     NervesHub currently runs with Postgres 10.7. For development, you can use a local postgres or use the configured docker image:

     **Using Docker**

     * Create directory for local data storage: `mkdir ~/db`
     * Start the database (may require sudo): `docker-compose up -d`

     **Using local postgres**

     * Make sure your postgres is running
     * Copy `dev.env` to `.env` with `cp dev.env .env`
     * Change any of the `DB_*` variables as needed in your `.env`. For local running postgres, you would typically use these settings:

     ```bash
     DB_USER=postgres
     DB_PASSWORD="" # in some cases, this might not be blank
     DB_PORT=5432
     ```

2. Fetch dependencies: `mix do deps.get, compile`
3. Initialize the database: `make reset-db` (or mix `ecto.reset`)
4. Compile web assets (this only needs to be done once and requires python2 or a symlink for python3):
   `mix assets.install`

### Starting the application

* `make server` - start the server process (or run `mix phx.server`)
* `make iex-server` - start the server with the interactive shell (or run `iex -S mix phx.server`)

> **_Note_**: The whole app may need to be compiled the first time you run this, so please be patient

Once the server is running, by default in development you can access it at http://localhost:4000

In development you can login into a pre-generated account with the username
`nerveshub` and password `nerveshub`.

### Running Tests

1. Make sure you've completed your [database connection setup](#development-environment-setup)
2. Fetch and compile `test` dependencies: `MIX_ENV=test mix do deps.get, compile`
3. Initialize the test databases: `make reset-test-db`
4. Run tests: `make test`


### Client-side SSL device authorization

NervesHub uses Client-side SSL to authorize and identify connected devices.
Devices are required to provide a valid certificate that was signed using the
trusted certificate authority NervesHub certificate. This certificate should be
generated and kept secret and private from Internet-connected servers.

For convenience, we use the pre-generated certificates for `dev` and `test`.
Production certificates can be generated by following the SSL certificate
instructions in `test/fixtures/README.md` and setting the following environment
variables to point to the generated key and certificate paths on the server.

```text
NERVESHUB_SSL_KEY
NERVESHUB_SSL_CERT
NERVESHUB_SSL_CACERT
```

### Tags

Tags are arbitrary strings, such as `"stable"` or `"beta"`. They can be added to
Devices and Firmware.

For a Device to be considered eligible for a given Deployment, it must have
*all* the tags in the Deployment's "tags" condition.

### Potential SSL issues

OTP > 24.2.2 switched to use TLS1.3 by default and made quite a few fixes/changes
to how it is implemented in the `:ssl` module. This has affected the setup of
client authentication in a few different ways depending on how you have your
server and device configured:

| Server | Client | Effect |
| --- | --- | --- |
|TLS1.3 | TLS1.3| `certificate_required` error (needs OTP 25.2 - see https://github.com/erlang/otp/issues/6106)  |
|TLS1.3|TLS1.2|  `CLIENT ALERT: Fatal - Handshake Failure - :unacceptable_ecdsa_key` - Happens because the client is attempting to sign with `:she` as the signature algorithm. The workaround is to specify `ssl: [signature_algs: [{:sha256, :ecdsa},{:sha512, :ecdsa}]]`|
|TLS1.2 | TLS1.3 or TLS1.2 | Successful|
