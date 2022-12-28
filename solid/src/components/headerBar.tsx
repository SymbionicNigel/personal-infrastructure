import AppBar from '@suid/material/AppBar';
import IconButton from '@suid/material/IconButton';
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
	);
}
