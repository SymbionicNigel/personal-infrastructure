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
			<Fab
				variant='extended'
				color='primary'

				// sx={{ position: '', bottom: '2rem', left: '2rem' }}
			/>
			<Fab
				variant='extended'
				color='secondary'
				// sx={{ position: 'fixed', bottom: '2rem', left: '2rem' }}
			/>
			<Fab
				variant='extended'
				color='success'
				// sx={{ position: 'fixed', bottom: '2rem', left: '2rem' }}
			/>
			<Fab
				variant='extended'
				color='warning'
				// sx={{ position: 'fixed', bottom: '2rem', left: '2rem' }}
			/>
		</Stack>
	);
}
