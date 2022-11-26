# SolidStart

Everything you need to build a Solid project, powered by [`solid-start`](https://start.solidjs.com);

## Creating a project

```bash
# create a new project in the current directory
npm init solid

# create a new project in my-app
npm init solid my-app
```

## Developing

Once you've created a project and installed dependencies with `npm install` (or `pnpm install` or `yarn`), start a development server:

```bash
npm run dev

# or start the server and open the app in a new browser tab
npm run dev -- --open
```

## Building

Solid apps are built with _adapters_, which optimise your project for deployment to different environments.

By default, `npm run build` will generate a Node app that you can run with `npm start`. To use a different adapter, add it to the `devDependencies` in `package.json` and specify in your `vite.config.js`.

## Packages/Frameworks in use

- [SolidJS](https://www.solidjs.com/docs/latest/api)
- [Solid Start](https://start.solidjs.com/getting-started/what-is-solidstart)
- [Prisma](https://www.prisma.io/)
- [SUID (Solid port of MaterialUI)](https://suid.io/)

> Keep an eye out on this repo for potentially useful packages <https://github.com/one-aalam/awesome-solid-js>
