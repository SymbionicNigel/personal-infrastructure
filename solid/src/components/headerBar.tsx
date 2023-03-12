import AppBar from '@suid/material/AppBar';
import Stack from '@suid/material/Stack';
import FullScreen from '@suid/icons-material/Fullscreen';
import FullscreenExit from '@suid/icons-material/FullscreenExit';
import Typography from '@suid/material/Typography';
import Button from '@suid/material/Button';
import { useNavigate } from 'solid-start';
import { useTheme } from '@suid/material';
import { useWindowScrollPosition } from '@solid-primitives/scroll';
import { createEffect, createSignal } from 'solid-js';
import { createFullscreen } from '@solid-primitives/fullscreen';
import HeaderCrumbs from './breadCrumbs';

export default function HeaderBar() {
	const navigate = useNavigate();
	const scroll = useWindowScrollPosition();
	const [headerVariant, setHeaderVariant] = createSignal<1 | 2 | 3 | 4>(1);
	const [fullscreen, setFullscreen] = createSignal(false);
	const theme = useTheme();

	createEffect(() => {
		const REM = 16;
		if (scroll.y >= 4 * REM) setHeaderVariant(4);
		else if (4 * REM > scroll.y && scroll.y >= 3 * REM) setHeaderVariant(3);
		else if (3 * REM > scroll.y && scroll.y >= REM * 0.5) setHeaderVariant(2);
		else if (REM * 0.5 >= scroll.y) setHeaderVariant(1);
	});

	const toggleFullscreen = () => {
		setFullscreen(!fullscreen());
		createFullscreen(document.documentElement, fullscreen);
	};

	return (
		<AppBar
			class='header'
			position='sticky'
			sx={{
				top: '-4rem;',
				height: '9rem;',
				backgroundColor: theme.palette.primary.main,
			}}
		>
			<Stack
				textTransform='capitalize'
				width='100%'
				alignItems='center'
				justifyContent=''
				direction='column'
				position='absolute'
				bottom={0}
			>
				<Stack
					direction='row'
					justifyContent='space-between'
					alignItems='center'
					height='fit-content'
					spacing={4}
					width='100%'
				>
					<Button
						color='inherit'
						aria-label='fullscreen'
						sx={{ width: '2.5rem' }}
						startIcon={fullscreen() ? <FullscreenExit /> : <FullScreen />}
						onclick={toggleFullscreen}
					/>
					<Typography
						variant={`h${headerVariant()}`}
						component={`h${headerVariant()}`}
					>
						Symbionic.Tech
					</Typography>
					<Button
						sx={{ width: 'auto' }}
						type='button'
						size='large'
						color='inherit'
						onclick={() => navigate('/login')}
					>
						Login
					</Button>
				</Stack>
				<HeaderCrumbs />
			</Stack>
		</AppBar>
	);
}
