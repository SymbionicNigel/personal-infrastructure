import { useNavigate } from 'solid-start';
import { useLocation } from 'solid-start/router';
import { Breadcrumbs, Link } from '@suid/material';
import { createMemo, createSignal, Index, JSX } from 'solid-js';

export default function HeaderCrumbs() {
	const navigate = useNavigate();
	const location = useLocation();
	const [crumbs, setCrumbs] = createSignal<string[]>([]);
	const _pathname = createMemo(() =>
		setCrumbs([
			'Home',
			...location.pathname
				.split('/')
				.filter((x) => x)
				.map((x) => x.charAt(0).toUpperCase() + x.slice(1)),
		])
	);

	const navigateToCrumb = (index: number) =>
		navigate(
			crumbs()
				.slice(1, index + 1)
				.map((x) => x.toLowerCase())
				.join('/')
		);

	return (
		<Breadcrumbs
			maxItems={4}
			aria-label='breadcrumb'
			sx={{ height: 'fit-content' }}
		>
			<Index each={_pathname()}>
				{(crumb, i) => (
					<Link
						underline='hover'
						variant='h6'
						onClick={() => navigateToCrumb(i)}
						color='Background'
					>
						{crumb()}
					</Link>
				)}
			</Index>
		</Breadcrumbs>
	);
}
