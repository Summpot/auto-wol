export type WolTask = {
	id: string;
	macAddress: string;
	status: "pending" | "processing" | "success" | "failed";
	createdAt: number;
	updatedAt: number;
	attempts: number;
};

export type WolRequest = {
	macAddress: string;
};

export type Message =
	| {
			type: "add-task";
			task: WolTask;
	  }
	| {
			type: "update-task";
			task: WolTask;
	  }
	| {
			type: "all-tasks";
			tasks: WolTask[];
	  };

export type RouterOSWolResponse = {
	tasks: {
		macAddress: string;
		id: string;
	}[];
};
