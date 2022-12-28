import HeaderBar from '~/components/headerBar';
import { useUser } from '../db/useUser';

export function routeData() {
	return useUser();
}

export default function Home() {
	// const user = useRouteData<typeof routeData>();
	// const [, { Form }] = createServerAction$((f: FormData, { request }) =>
	// 	logout(request)
	// );

	return (
		<main><HeaderBar/></main>
	);
}
