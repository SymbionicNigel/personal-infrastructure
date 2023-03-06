import { Stack } from '@suid/material';
import Fab from '@suid/material/Fab';

export default function SideMenu() {
	return (
		<Stack
			alignContent='flex-start'
			position='fixed'
			bottom='2rem'
			left='2rem'
			gap='1rem'
			zIndex='1000'
		>
			<Fab variant='extended' color='primary' />
			<Fab variant='extended' color='secondary' />
			<Fab variant='extended' color='success' />
			<Fab variant='extended' color='warning' />
		</Stack>
	);
}
