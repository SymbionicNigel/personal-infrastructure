import { IconButton, Link, Stack, useTheme } from '@suid/material';
import Fab from '@suid/material/Fab';
import { Close, ReceiptLong, Widgets } from '@suid/icons-material';
import { createSignal, Show } from 'solid-js';
import { useLocation, useNavigate } from 'solid-start';

export default function SideMenu() {
	const navigate = useNavigate();
	const location = useLocation();
	const [expanded, setExpanded] = createSignal(false);
	const theme = useTheme();

	const clickExpanded = () => {
		setExpanded(!expanded());
	};

	const handleMenuClick = (destination: string) => {
		if (destination !== location.pathname) {
			navigate(destination);
			clickExpanded();
		}
	};

	return (
		<Stack
			alignContent='flex-start'
			position='fixed'
			bottom='2rem'
			left='2rem'
			gap='0.5rem'
			zIndex='1000'
		>
			<Show
				when={expanded()}
				fallback={
					<Fab variant='extended' color='secondary' onclick={clickExpanded}>
						<Widgets />
					</Fab>
				}
			>
				<Link
					underline='hover'
					variant='h3'
					color={theme.palette.secondary.dark}
					onClick={() => handleMenuClick('/resume')}
				>
					<ReceiptLong fontSize='large' />
					Résumé
					<Show when={location.pathname === '/resume'}>&middot</Show>
				</Link>
				<IconButton
					sx={{ width: 'fit-content' }}
					color='secondary'
					onClick={clickExpanded}
					type='button'
					size='large'
				>
					<Close />
				</IconButton>
			</Show>
		</Stack>
	);
}
