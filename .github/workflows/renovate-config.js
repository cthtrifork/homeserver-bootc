module.exports = {
  "repositories": [
    "cthtrifork/homeserver-bootc",
    "cthtrifork/pmx01-talos-gitops"
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
