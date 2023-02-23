// @refresh reload
import { CssBaseline, ThemeProvider } from '@suid/material';
import { Suspense } from 'solid-js';
import {
	Body,
	ErrorBoundary,
	FileRoutes,
	Head,
	Html,
	Link,
	Meta,
	Routes,
	Scripts,
	Title,
} from 'solid-start';
import { Router } from '@solidjs/router';
import HeaderBar from './components/headerBar';
import SideMenu from './components/sideMenu';
import './root.css';
import { mantanaRegular60s } from './themes';

export default function Root() {
	return (
		<Html lang='en'>
			<Head>
				<Title>Symbionic.tech</Title>
				<Meta charset='utf-8' />
				<Meta name='viewport' content='width=device-width, initial-scale=1' />
				<Meta name='theme-color' content='#000000' />
				<Link
					href='/fonts/MantanaItalic.otf'
					rel='preload'
					type='font/otf'
					as='font'
				/>
				<Link
					href='/fonts/MantanaRegular.otf'
					rel='preload'
					type='font/otf'
					as='font'
				/>
				<Link
					href='https://fonts.googleapis.com/css?family=Roboto:300,400,500'
					rel='stylesheet'
				/>
				{/* TODO: Need to add in and test proper web manifest for pwa installability */}
				{/* <Link rel='manifest' href='/symbionic.webmanifest' /> */}
			</Head>
			<Body>
				<noscript>You need to enable JavaScript to run this app.</noscript>
				<ErrorBoundary>
					<Suspense fallback={<div>Loading</div>}>
						<ThemeProvider theme={mantanaRegular60s}>
							<CssBaseline />
							<Router>
								<HeaderBar />
								<SideMenu />
								<main>
									<Routes>
										<FileRoutes />
									</Routes>
								</main>
							</Router>
						</ThemeProvider>
					</Suspense>
				</ErrorBoundary>
				<Scripts />
			</Body>
		</Html>
	);
}
