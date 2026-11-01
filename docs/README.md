# Kre: documentation

**What exists and what is in progress: [FEATURES.md](FEATURES.md).** All example controllers in one server: `examples/showcase`. The whole application: `examples/shelter`: JWT login, roles, `[@@authorize]`, `[@@transactional]`, live loaders, MariaDB via sqlgg, a Melange client.

The code in each chapter is the files of `examples/cats` and `docs/examples`, which are built and checked by tests; mdx makes sure the text in a chapter matches the file.

**Overview:** [First steps](first-steps.md) · [Controllers](controllers.md) · [Providers](providers.md) · [Modules](modules.md) · [Middleware](middleware.md) · [Exception filters](exception-filters.md) · [Pipes](pipes.md) · [Guards](guards.md) · [Interceptors](interceptors.md) · [Custom decorators](custom-decorators.md)

**Fundamentals:** [Custom providers](custom-providers.md) · [Async providers and dynamic modules](dynamic-modules.md) · [Injection scopes](injection-scopes.md) · [Execution context](execution-context.md) · [Lifecycle events](lifecycle-events.md) · [Testing](testing.md) · [What is not needed and why](not-needed.md)

**WebSockets:** [Gateways](websockets.md)

**Security:** [Authentication and Authorization](authentication.md) · [Secure headers, CORS, rate limiting](security.md)

**Techniques:** [Configuration](configuration.md) · [Commands](commands.md) · [Events](events.md) · [Queues](jobs.md) · [Mail](mail.md) · [Workflow](workflow.md) · [Task scheduling](task-scheduling.md) · [Caching](caching.md) · [Actuator and health](actuator.md) · [Profiler](profiler.md) · [Validation](validation.md) · [Serialization](serialization.md) · [Data](data.md) · [Live loaders](live.md)

**OpenAPI, CLI, client:** [OpenAPI and CLI](openapi-cli.md) · [Client and router](client.md) · [HTTP client for third-party APIs](http-client.md)
