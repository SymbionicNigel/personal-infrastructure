import { IconButton, Link, Stack, useTheme } from '@suid/material';
import Fab from '@suid/material/Fab';
import {
	Close,
	ReceiptLong,
	Widgets,
	BungalowOutlined,
	PsychologyOutlined,
	BookOutlined,
	ConnectWithoutContactOutlined,
} from '@suid/icons-material';
import { createSignal, Show } from 'solid-js';
import { useLocation, useNavigate } from 'solid-start';

export default function SideMenu() {
	const navigate = useNavigate();
	const location = useLocation();
	const [expanded, setExpanded] = createSignal(true);
	const theme = useTheme();

	const clickExpanded = () => {
		setExpanded(!expanded());
	};

	const handleMenuClick = (destination: string) => {
		if (destination !== location.pathname) {
			navigate(destination);
			// clickExpanded();
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
					onClick={() => handleMenuClick('/#')}
				>
					<BungalowOutlined fontSize='large' />
					Home
					<Show when={location.pathname === '/'}>&middot</Show>
				</Link>
				<Link
					underline='hover'
					variant='h3'
					color={theme.palette.secondary.dark}
					onClick={() => handleMenuClick('/nigel#')}
				>
					<PsychologyOutlined fontSize='large' />
					Nigel
					<Show when={location.pathname === '/nigel'}>&middot</Show>
				</Link>
				<Link
					underline='hover'
					variant='h3'
					color={theme.palette.secondary.dark}
					onClick={() => handleMenuClick('/resume#')}
				>
					<ReceiptLong fontSize='large' />
					Résumé
					<Show when={location.pathname === '/resume'}>&middot</Show>
				</Link>
				<Link
					underline='hover'
					variant='h3'
					color={theme.palette.secondary.dark}
					onClick={() => handleMenuClick('/portfolio#')}
				>
					<BookOutlined fontSize='large' />
					Portfolio
					<Show when={location.pathname === '/portfolio'}>&middot</Show>
				</Link>
				<Link
					underline='hover'
					variant='h3'
					color={theme.palette.secondary.dark}
					onClick={() => handleMenuClick('/contact#')}
				>
					<ConnectWithoutContactOutlined fontSize='large' />
					Connect
					<Show when={location.pathname === '/contact'}>&middot</Show>
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
