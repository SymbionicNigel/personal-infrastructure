import AppBar from '@suid/material/AppBar';
import Stack from '@suid/material/Stack';
import FullScreen from '@suid/icons-material/Fullscreen';
import FullscreenExit from '@suid/icons-material/FullscreenExit';
import Code from '@suid/icons-material/Code';
import Typography from '@suid/material/Typography';
import Button from '@suid/material/Button';
import { useNavigate } from 'solid-start';
import { useTheme } from '@suid/material';
import { createEffect, createSignal } from 'solid-js';
import { useWindowScrollPosition } from '@solid-primitives/scroll';
import { createFullscreen } from '@solid-primitives/fullscreen';
import HeaderCrumbs from './breadCrumbs';
import test from '../../public/images/printable.svg';

export default function HeaderBar() {
	// TODO: make the header react to its width shrinking, changing the Stacks' directions to column
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
					flexWrap='wrap'
					width='100%'
				>
					<Typography
						variant={`h${headerVariant()}`}
						component={`h${headerVariant()}`}
					>
						Symbionic.Tech
					</Typography>
					<div>
						{/* Add Printables Button https://www.printables.com/assets/loading/loading-wheel-4s.svg 
						trigger animation on mouseover */}
						{/* <svg ='https://www.printables.com/assets/loading/loading-wheel-4s.svg'  /> */}

						<Button
							color='inherit'
							aria-label='fullscreen'
							sx={{ width: '2rem' }}
							startIcon={
								<img
									id='x'
									src={test}
									// src='https://www.printables.com/assets/loading/loading-wheel-4s.svg'
									width={'55rem;'}
									onMouseOver={() => {
										console.log(document.getElementById('x')?.animate([]));
										// document.getElementById('trans2').beginElement();
										// setTimeout(
										// 	document.getElementById('trans1')?.beginElement(),
										// 	150
										// );
									}}
								/>
							}
							onclick={() =>
								(window.location.href = 'https://github.com/SymbionicNigel')
							}
						/>
						{/* Add LinkedIn Button*/}
						<Button
							color='inherit'
							aria-label='fullscreen'
							sx={{ width: '2.5rem' }}
							startIcon={fullscreen() ? <FullscreenExit /> : <FullScreen />}
							onclick={toggleFullscreen}
						/>
						<Button
							sx={{ width: 'auto' }}
							type='button'
							size='large'
							color='inherit'
							onclick={() => navigate('/login')}
						>
							Login
						</Button>
					</div>
				</Stack>
				<HeaderCrumbs />
			</Stack>
		</AppBar>
	);
}
