module.exports = {
  "repositories": [
    "cthtrifork/homeserver-bootc",
  ],
  hostRules: [
    {
      "hostType": 'docker',
      "matchHost": 'ghcr.io',
      "username": 'cthtrifork',
      "password": process.env.RENOVATE_PAT_TOKEN,
    }
  ]
}
