import { createServerData$, redirect } from 'solid-start/server';
import { getUser, logout } from './session';

export const useUser = () =>
	createServerData$(async (_, { request }) => {
		const user = await getUser(request);
		if (request.url.startsWith('/login') || user) throw logout(request);
		return user;
	});
