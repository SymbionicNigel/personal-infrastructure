import prisma from './PrismaService';
import { redirect } from 'solid-start/server';
import { createCookieSessionStorage } from 'solid-start/session';
type LoginForm = {
  username: string;
  password: string;
};

export async function register({ username, password }: LoginForm) {
	return prisma.user.create({
		data: { username: username, password },
	});
}

export async function login({ username, password }: LoginForm) {
	const user = await prisma.user.findUnique({ where: { username } });
	if (!user) return null;
	const isCorrectPassword = password === user.password;
	if (!isCorrectPassword) return null;
	return user;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const sessionSecret = import.meta.env.SESSION_SECRET;

const storage = createCookieSessionStorage({
	cookie: {
		name: 'RJ_session',
		// secure doesn't work on localhost for Safari
		// https://web.dev/when-to-use-local-https/
		secure: true,
		secrets: ['hello'], // TODO: generate secret value and store in vault
		sameSite: 'strict',
		path: '/',
		maxAge: 60 * 60 * 24 * 30,
		httpOnly: true,
	},
});

export function getUserSession(request: Request) {
	return storage.getSession(request.headers.get('Cookie'));
}

export async function getUserId(request: Request) {
	const session = await getUserSession(request);
	const userId = session.get('userId');
	if (!userId || typeof userId !== 'string') return null;
	return userId;
}

export async function requireUserId(
	request: Request,
	redirectTo: string = new URL(request.url).pathname
) {
	const session = await getUserSession(request);
	const userId = session.get('userId');
	if (!userId || typeof userId !== 'string') {
		const searchParams = new URLSearchParams([['redirectTo', redirectTo]]);
		throw redirect(`/login?${searchParams}`);
	}
	return userId;
}

export async function getUser(_request: Request) {
	return null; // Until we implement logins
	// const userId = await getUserId(request);
	// if (typeof userId !== 'string') {
	// 	return null;
	// }

	// try {
	// 	const user = await prisma.user.findUnique({ where: { id: userId } });
	// 	return user;
	// } catch {
	// 	throw logout(request);
	// }
}

export async function logout(request: Request) {
	const session = await storage.getSession(request.headers.get('Cookie'));
	return redirect('/', {
		headers: {
			'Set-Cookie': await storage.destroySession(session),
		},
	});
}

export async function createUserSession(userId: string, redirectTo: string) {
	const session = await storage.getSession();
	session.set('userId', userId);
	return redirect(redirectTo, {
		headers: {
			'Set-Cookie': await storage.commitSession(session),
		},
	});
}
