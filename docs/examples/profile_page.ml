let respond profile = Kre.Response.json ~status:`OK (module Profile) profile
