import {
	StartServer,
	createHandler,
	renderAsync,
} from 'solid-start/entry-server';
import 'reflect-metadata';

export default createHandler(
	renderAsync((event) => <StartServer event={event} />)
);
