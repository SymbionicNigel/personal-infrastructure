// import { Button } from '@suid/material';
// import { refetchRouteData, useRouteData } from 'solid-start';
// import { createServerAction$ } from 'solid-start/server';
// import { logout } from '~/db/session';
import MenuIcon from '@suid/icons-material/Menu';
import { AppBar, Button, IconButton, Stack, Toolbar, Typography } from '@suid/material';
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
		<main>
			<AppBar position='static'>
				<Stack
					direction="row"
					justifyContent="space-between"
					alignItems="center"
					spacing={4}
				>
					<IconButton
						color='inherit'
						aria-label="menu"
						sx={{width: '2.5rem'}}
					>
						<MenuIcon/>
					</IconButton>
					<Typography variant="h6" component="div">
						Symbionic 
					</Typography>
					<Button
						sx={{ width: 'auto' }}
						type='button'
						size='small'
						color="inherit">
						Login
					</Button>
				</Stack>
			</AppBar>
		</main>
	);
}
