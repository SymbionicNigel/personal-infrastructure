import AppBar from '@suid/material/AppBar';
import Stack from '@suid/material/Stack';
import MenuIcon from '@suid/icons-material/Menu';
import Typography from '@suid/material/Typography';
import Button from '@suid/material/Button';
import { useNavigate } from 'solid-start';
import { Breadcrumbs, Link, useTheme } from '@suid/material';
import { useWindowScrollPosition } from '@solid-primitives/scroll';
import { createEffect, createSignal } from 'solid-js';

export default function HeaderBar() {
	const navigate = useNavigate();
	const scroll = useWindowScrollPosition();
	const [headerVariant, setHeaderVariant] = createSignal<1 | 2 | 3 | 4>(1);
	const theme = useTheme();
	createEffect(() => {
		const REM = 16;
		let headerSize = headerVariant();
		if (scroll.y >= 4 * REM) headerSize = 4;
		else if (4 * REM > scroll.y && scroll.y >= 3 * REM) headerSize = 3;
		else if (3 * REM > scroll.y && scroll.y >= REM * 0.5) headerSize = 2;
		else if (REM * 0.5 >= scroll.y) headerSize = 1;
		setHeaderVariant(headerSize);
	});

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
						aria-label='menu'
						sx={{ width: '2.5rem' }}
						startIcon=<MenuIcon />
						onclick={() => navigate('/resume')}
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
				<Breadcrumbs
					maxItems={4}
					aria-label='breadcrumb'
					sx={{ height: 'fit-content' }}
				>
					<Link
						underline='hover'
						href='/#'
						variant='h6'
						onclick={() => navigate('/#')}
						color='Background'
					>
						Home
					</Link>
				</Breadcrumbs>
			</Stack>
		</AppBar>
	);
}
