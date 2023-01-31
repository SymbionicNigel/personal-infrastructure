import AppBar from '@suid/material/AppBar';
import Stack from '@suid/material/Stack';
import MenuIcon from '@suid/icons-material/Menu';
import Typography from '@suid/material/Typography';
import Button from '@suid/material/Button';

export default function HeaderBar() {
	return (
		<AppBar position='static'>
			<Stack
				direction="row"
				justifyContent="space-between"
				alignItems="center"
				spacing={4}
			>
				<Button
					color='inherit'
					aria-label='menu'
					sx={{width: '2.5rem'}}
					startIcon=<MenuIcon/>
					href='/resume' />
				<Typography variant="h5" component="div">
					Symbionic
				</Typography>
				<Button
					sx={{ width: 'auto' }}
					type='button'
					size='small'
					color="inherit"
				>
					Login
				</Button>
			</Stack>
		</AppBar>
	);
}
